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
        mediaKeyPlayer: MediaKeyControllablePlayer.runningOutputPlayer()
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
    MediaKeyControllablePlayer(bundleIdentifier: "app.podcast.cosmos", displayName: "小宇宙"),
    MediaKeyControllablePlayer(
      bundleIdentifier: "com.apple.Safari",
      displayName: "Safari",
      outputBundleIdentifiers: [
        "com.apple.Safari",
        "com.apple.WebKit.GPU",
        "com.apple.WebKit.WebContent",
        "com.apple.WebKit.WebContent.EnhancedSecurity"
      ],
      ignoresOutputWhileInputRunning: true
    ),
    MediaKeyControllablePlayer(
      bundleIdentifier: "com.google.Chrome",
      displayName: "Chrome",
      outputBundleIdentifiers: [
        "com.google.Chrome",
        "com.google.Chrome.helper",
        "com.google.Chrome.helper.renderer"
      ],
      ignoresOutputWhileInputRunning: true
    ),
    MediaKeyControllablePlayer(
      bundleIdentifier: "com.microsoft.edgemac",
      displayName: "Edge",
      outputBundleIdentifiers: [
        "com.microsoft.edgemac",
        "com.microsoft.edgemac.helper",
        "com.microsoft.edgemac.helper.renderer"
      ],
      ignoresOutputWhileInputRunning: true
    ),
    MediaKeyControllablePlayer(
      bundleIdentifier: "com.brave.Browser",
      displayName: "Brave",
      outputBundleIdentifiers: [
        "com.brave.Browser",
        "com.brave.Browser.helper",
        "com.brave.Browser.helper.renderer"
      ],
      ignoresOutputWhileInputRunning: true
    ),
    MediaKeyControllablePlayer(
      bundleIdentifier: "org.mozilla.firefox",
      displayName: "Firefox",
      outputBundleIdentifiers: [
        "org.mozilla.firefox",
        "org.mozilla.plugincontainer"
      ],
      ignoresOutputWhileInputRunning: true
    ),
    MediaKeyControllablePlayer(
      bundleIdentifier: "company.thebrowser.Browser",
      displayName: "Arc",
      outputBundleIdentifiers: [
        "company.thebrowser.Browser",
        "company.thebrowser.Browser.helper",
        "company.thebrowser.Browser.helper.renderer"
      ],
      ignoresOutputWhileInputRunning: true
    ),
    MediaKeyControllablePlayer(
      bundleIdentifier: "com.tabbit-ai.Tabbit",
      displayName: "Tabbit",
      outputBundleIdentifiers: [
        "com.tabbit-ai.Tabbit",
        "com.tabbit-ai.Tabbit.helper"
      ],
      ignoresOutputWhileInputRunning: true
    ),
    MediaKeyControllablePlayer(
      bundleIdentifier: "com.openai.atlas",
      displayName: "ChatGPT Atlas",
      runningBundleIdentifiers: [
        "com.openai.atlas",
        "com.openai.atlas.web"
      ],
      outputBundleIdentifiers: [
        "com.openai.atlas",
        "com.openai.atlas.web",
        "com.openai.atlas.web.helper",
        "com.openai.atlas.web.helper.renderer",
        "com.openai.atlas.web.helper.plugin"
      ],
      ignoresOutputWhileInputRunning: true
    ),
    MediaKeyControllablePlayer(
      bundleIdentifier: "company.thebrowser.dia",
      displayName: "Dia",
      outputBundleIdentifiers: [
        "company.thebrowser.dia",
        "company.thebrowser.browser.helper",
        "company.thebrowser.browser.helper.renderer"
      ],
      ignoresOutputWhileInputRunning: true
    )
  ]

  var bundleIdentifier: String
  var displayName: String
  var runningBundleIdentifiers: [String]
  var outputBundleIdentifiers: [String]
  var ignoresOutputWhileInputRunning: Bool

  init(
    bundleIdentifier: String,
    displayName: String,
    runningBundleIdentifiers: [String]? = nil,
    outputBundleIdentifiers: [String]? = nil,
    ignoresOutputWhileInputRunning: Bool = false
  ) {
    self.bundleIdentifier = bundleIdentifier
    self.displayName = displayName
    self.runningBundleIdentifiers = runningBundleIdentifiers ?? [bundleIdentifier]
    self.outputBundleIdentifiers = outputBundleIdentifiers ?? [bundleIdentifier]
    self.ignoresOutputWhileInputRunning = ignoresOutputWhileInputRunning
  }

  static func runningOutputPlayer() -> MediaKeyControllablePlayer? {
    supportedPlayers.first { player in
      player.isRunning
        && CoreAudioDeviceQuery.isOutputRunning(forBundleIdentifiers: player.outputBundleIdentifiers)
        && !player.isUsingInputWhileOutputShouldBeIgnored
    }
  }

  var isRunning: Bool {
    let runningBundleIdentifierSet = Set(runningBundleIdentifiers)
    return NSWorkspace.shared.runningApplications.contains { application in
      guard let bundleIdentifier = application.bundleIdentifier else {
        return false
      }

      return runningBundleIdentifierSet.contains(bundleIdentifier)
    }
  }

  private var isUsingInputWhileOutputShouldBeIgnored: Bool {
    ignoresOutputWhileInputRunning
      && CoreAudioDeviceQuery.isInputRunning(forBundleIdentifiers: outputBundleIdentifiers)
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
