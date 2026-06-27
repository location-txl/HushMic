import AppKit
import Darwin
import Foundation

enum ReliablePlaybackState {
  case playing
  case notPlaying
}

struct MediaPlaybackStatus {
  var state: ReliablePlaybackState?
  var player: ScriptableMediaPlayer?
  var mediaKeyPlayer: MediaKeyControllablePlayer?
}

final class MediaPlaybackStateProvider {
  private let mediaRemoteReader = MediaRemotePlaybackStateReader()

  func currentStatus() -> MediaPlaybackStatus {
    var pausedPlayer: ScriptableMediaPlayer?

    for player in ScriptableMediaPlayer.supportedPlayers where player.isRunning {
      guard let state = player.playbackState() else {
        continue
      }

      if state == .playing {
        return MediaPlaybackStatus(state: .playing, player: player)
      }

      pausedPlayer = pausedPlayer ?? player
    }

    let mediaRemoteState = mediaRemoteReader.playbackState()
    if mediaRemoteState == .playing {
      return MediaPlaybackStatus(
        state: .playing,
        player: nil,
        mediaKeyPlayer: MediaKeyControllablePlayer.runningPlayer()
      )
    }

    if let mediaKeyPlayer = MediaKeyControllablePlayer.runningOutputPlayer() {
      return MediaPlaybackStatus(state: .playing, player: nil, mediaKeyPlayer: mediaKeyPlayer)
    }

    if let mediaRemoteState {
      return MediaPlaybackStatus(state: mediaRemoteState, player: nil, mediaKeyPlayer: nil)
    }

    if let pausedPlayer {
      return MediaPlaybackStatus(state: .notPlaying, player: pausedPlayer, mediaKeyPlayer: nil)
    }

    return MediaPlaybackStatus(state: nil, player: nil, mediaKeyPlayer: nil)
  }
}

struct ScriptableMediaPlayer: Equatable {
  static let supportedPlayers = [
    ScriptableMediaPlayer(bundleIdentifier: "com.apple.Music", displayName: "Music"),
    ScriptableMediaPlayer(bundleIdentifier: "com.spotify.client", displayName: "Spotify"),
    ScriptableMediaPlayer(bundleIdentifier: "com.apple.iTunes", displayName: "iTunes")
  ]

  var bundleIdentifier: String
  var displayName: String

  var isRunning: Bool {
    NSWorkspace.shared.runningApplications.contains { application in
      application.bundleIdentifier == bundleIdentifier
    }
  }

  func playbackState() -> ReliablePlaybackState? {
    guard let value = runAppleScript("tell application id \"\(bundleIdentifier)\" to return player state as string") else {
      return nil
    }

    switch value.lowercased() {
    case "playing":
      return .playing
    case "paused", "stopped":
      return .notPlaying
    default:
      return nil
    }
  }

  func pause() -> Bool {
    runAppleScript("tell application id \"\(bundleIdentifier)\" to pause") != nil
  }

  func play() -> Bool {
    runAppleScript("tell application id \"\(bundleIdentifier)\" to play") != nil
  }

  private func runAppleScript(_ source: String) -> String? {
    var error: NSDictionary?
    guard let descriptor = NSAppleScript(source: source)?.executeAndReturnError(&error), error == nil else {
      return nil
    }

    return descriptor.stringValue ?? ""
  }
}

struct MediaKeyControllablePlayer: Equatable {
  static let supportedPlayers = [
    MediaKeyControllablePlayer(bundleIdentifier: "app.podcast.cosmos", displayName: "小宇宙")
  ]

  var bundleIdentifier: String
  var displayName: String

  static func runningPlayer() -> MediaKeyControllablePlayer? {
    supportedPlayers.first { $0.isRunning }
  }

  static func runningOutputPlayer() -> MediaKeyControllablePlayer? {
    supportedPlayers.first { player in
      player.isRunning && CoreAudioDeviceQuery.isOutputRunning(forBundleIdentifier: player.bundleIdentifier)
    }
  }

  var isRunning: Bool {
    NSWorkspace.shared.runningApplications.contains { application in
      application.bundleIdentifier == bundleIdentifier
    }
  }
}

private final class MediaRemotePlaybackStateReader {
  private typealias PlaybackStateCallback = @convention(block) (Int32) -> Void
  private typealias GetPlaybackState = @convention(c) (DispatchQueue, PlaybackStateCallback) -> Void

  private let callbackQueue = DispatchQueue(label: "com.location.HushMic.mediaRemote")
  private lazy var getPlaybackState = loadGetPlaybackState()

  func playbackState() -> ReliablePlaybackState? {
    guard let getPlaybackState else {
      return nil
    }

    let semaphore = DispatchSemaphore(value: 0)
    let lock = NSLock()
    var rawState: Int32?

    let callback: PlaybackStateCallback = { state in
      lock.lock()
      rawState = state
      lock.unlock()
      semaphore.signal()
    }

    getPlaybackState(callbackQueue, callback)

    guard semaphore.wait(timeout: .now() + .milliseconds(200)) == .success else {
      return nil
    }

    lock.lock()
    let state = rawState
    lock.unlock()

    switch state {
    case 1:
      return .playing
    case 2, 3, 4:
      return .notPlaying
    default:
      return nil
    }
  }

  private func loadGetPlaybackState() -> GetPlaybackState? {
    let frameworkPaths = [
      "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote",
      "/System/Library/PrivateFrameworks/MediaRemote.framework/Versions/A/MediaRemote"
    ]

    for path in frameworkPaths {
      guard let handle = dlopen(path, RTLD_LAZY), let symbol = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationPlaybackState") else {
        continue
      }

      return unsafeBitCast(symbol, to: GetPlaybackState.self)
    }

    return nil
  }
}
