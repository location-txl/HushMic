import Combine
import Foundation

final class AppModel: ObservableObject {
  @Published private(set) var snapshot = MicrophoneSnapshot.unknown
  @Published private(set) var hasAccessibilityAccess = AccessibilityPermission.isTrusted
  @Published private(set) var lastAction = LocalizedMessage.key("action.listening")
  @Published private(set) var pausedByApp = false
  var onPermissionAuthorizationNeeded: (() -> Void)?

  @Published var launchAtLoginEnabled: Bool {
    didSet {
      guard didFinishInitializing, !isSyncingLaunchAtLogin, launchAtLoginEnabled != oldValue else {
        return
      }

      updateLaunchAtLogin(enabled: launchAtLoginEnabled, previousValue: oldValue)
    }
  }

  @Published var autoControlEnabled: Bool {
    didSet {
      UserDefaults.standard.set(autoControlEnabled, forKey: Self.autoControlDefaultsKey)

      if autoControlEnabled, !hasAccessibilityAccess {
        lastAction = .key("action.accessibility_missing")
        requestPermissionAuthorization()
      }
    }
  }

  private static let autoControlDefaultsKey = "autoControlEnabled"

  private let microphoneMonitor = MicrophoneMonitor()
  private let mediaController = MediaKeyPlaybackController()
  private let playbackStateProvider = MediaPlaybackStateProvider()
  private var microphoneSession: MicrophoneSession?
  private var permissionTimer: Timer?
  private var didFinishInitializing = false
  private var isSyncingLaunchAtLogin = false

  init() {
    autoControlEnabled = UserDefaults.standard.object(forKey: Self.autoControlDefaultsKey) as? Bool ?? true
    launchAtLoginEnabled = LaunchAtLoginService.isEnabled

    microphoneMonitor.onChange = { [weak self] snapshot in
      DispatchQueue.main.async {
        self?.handle(snapshot)
      }
    }
    microphoneMonitor.start()

    permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
      self?.refreshAccessibilityStatus()
    }

    didFinishInitializing = true
  }

  deinit {
    microphoneMonitor.stop()
    permissionTimer?.invalidate()
  }

  func statusTitle(localizer: AppLocalizer) -> String {
    if let errorMessage = snapshot.errorMessage {
      return localizer.text("status.monitor_error %@", errorMessage.resolve(with: localizer))
    }

    return snapshot.isActive ? localizer.text("status.mic_active") : localizer.text("status.mic_idle")
  }

  var menuBarIcon: String {
    if snapshot.errorMessage != nil {
      return "exclamationmark.triangle"
    }

    if snapshot.isActive {
      return autoControlEnabled ? "mic.fill" : "mic.fill.slash"
    }

    return autoControlEnabled ? "mic" : "mic.slash"
  }

  func deviceTitle(localizer: AppLocalizer) -> String {
    snapshot.primaryDeviceName(localizer: localizer)
  }

  func permissionTitle(localizer: AppLocalizer) -> String {
    hasAccessibilityAccess ? localizer.text("status.accessibility_granted") : localizer.text("status.accessibility_needed")
  }

  func lastActionTitle(localizer: AppLocalizer) -> String {
    lastAction.resolve(with: localizer)
  }

  func requestAccessibility() {
    hasAccessibilityAccess = AccessibilityPermission.requestPrompt()
    lastAction = hasAccessibilityAccess ? .key("action.accessibility_granted") : .key("action.accessibility_waiting")
  }

  func openAccessibilitySettings() {
    AccessibilityPermission.openSettings()
  }

  func requestPermissionAuthorizationFlow() {
    requestPermissionAuthorization()
  }

  func refresh() {
    refreshAccessibilityStatus()
    syncLaunchAtLoginStatus()
    microphoneMonitor.refresh()
  }

  func testPlayPause() {
    guard hasAccessibilityAccess else {
      lastAction = .key("action.accessibility_missing")
      requestPermissionAuthorization()
      return
    }

    lastAction = mediaController.sendPlayPause() ? .key("action.media_key_sent") : .key("action.media_key_failed")
  }

  private func handle(_ snapshot: MicrophoneSnapshot) {
    self.snapshot = snapshot
    refreshAccessibilityStatus()

    guard snapshot.errorMessage == nil else {
      return
    }

    if snapshot.isActive {
      startMicrophoneSessionIfNeeded()
      return
    }

    if microphoneSession != nil {
      finishMicrophoneSession()
    }
  }

  private func startMicrophoneSessionIfNeeded() {
    guard microphoneSession == nil else {
      return
    }

    microphoneSession = MicrophoneSession()
    pausedByApp = false
    pausePlaybackForMicrophone()
  }

  private func pausePlaybackForMicrophone() {
    guard autoControlEnabled else {
      lastAction = .key("action.auto_control_off")
      return
    }

    guard microphoneSession?.resumeTarget == nil else {
      return
    }

    guard permissionsReadyForPlaybackControl() else {
      return
    }

    let playbackStatus = playbackStateProvider.currentStatus()

    switch playbackStatus.state {
    case .some(.playing):
      if let player = playbackStatus.player, player.pause() {
        markPausedByApp(target: .scriptablePlayer(player))
        lastAction = .key("action.paused_player %@", [.raw(player.displayName)])
        return
      }

      pauseWithMediaKey(pausedPlayerName: playbackStatus.mediaKeyPlayer?.displayName)
    case .some(.notPlaying):
      lastAction = .key("action.music_already_paused")
    case .none:
      lastAction = .key("action.playback_unconfirmed")
    }
  }

  private func pauseWithMediaKey(pausedPlayerName: String? = nil) {
    guard mediaController.sendPlayPause() else {
      lastAction = .key("action.pause_media_key_failed")
      return
    }

    markPausedByApp(target: .mediaKey)
    lastAction = pausedPlayerName.map { .key("action.paused_player %@", [.raw($0)]) } ?? .key("action.paused")
  }

  private func markPausedByApp(target: ResumeTarget) {
    microphoneSession?.resumeTarget = target
    pausedByApp = true
  }

  private func finishMicrophoneSession() {
    let resumeTarget = microphoneSession?.resumeTarget
    microphoneSession = nil

    guard let resumeTarget else {
      pausedByApp = false
      lastAction = .key("action.mic_idle")
      return
    }

    resumePlaybackAfterMicrophone(target: resumeTarget)
  }

  private func resumePlaybackAfterMicrophone(target: ResumeTarget) {
    guard hasAccessibilityAccess else {
      pausedByApp = false
      lastAction = .key("action.accessibility_missing")
      requestPermissionAuthorization()
      return
    }

    let resumed: Bool

    switch target {
    case .scriptablePlayer(let player):
      guard player.isRunning else {
        pausedByApp = false
        lastAction = .key("action.resume_failed")
        return
      }

      guard PermissionAuthorizationService.hasAutomationPermission(for: player) else {
        pausedByApp = false
        lastAction = .key("action.automation_permission_missing")
        requestPermissionAuthorization()
        return
      }

      resumed = player.play()
    case .mediaKey:
      resumed = mediaController.sendPlayPause()
    }

    pausedByApp = false

    guard resumed else {
      lastAction = .key("action.resume_failed")
      return
    }

    lastAction = .key("action.resumed")
  }

  private func permissionsReadyForPlaybackControl() -> Bool {
    refreshAccessibilityStatus()

    guard hasAccessibilityAccess else {
      lastAction = .key("action.accessibility_missing")
      requestPermissionAuthorization()
      return false
    }

    guard PermissionAuthorizationService.runningPlayersNeedingAutomationPermission().isEmpty else {
      lastAction = .key("action.automation_permission_missing")
      requestPermissionAuthorization()
      return false
    }

    return true
  }

  private func refreshAccessibilityStatus() {
    hasAccessibilityAccess = AccessibilityPermission.isTrusted
  }

  private func requestPermissionAuthorization() {
    onPermissionAuthorizationNeeded?()
  }

  private func updateLaunchAtLogin(enabled: Bool, previousValue: Bool) {
    if let message = LaunchAtLoginService.setEnabled(enabled) {
      setLaunchAtLoginEnabledWithoutApplying(previousValue)
      lastAction = .key("action.login_item_error %@", [message])
    } else {
      lastAction = enabled ? .key("action.login_item_enabled") : .key("action.login_item_disabled")
    }
  }

  private func syncLaunchAtLoginStatus() {
    setLaunchAtLoginEnabledWithoutApplying(LaunchAtLoginService.isEnabled)
  }

  private func setLaunchAtLoginEnabledWithoutApplying(_ enabled: Bool) {
    isSyncingLaunchAtLogin = true
    launchAtLoginEnabled = enabled
    isSyncingLaunchAtLogin = false
  }

  private struct MicrophoneSession {
    var resumeTarget: ResumeTarget?
  }

  private enum ResumeTarget {
    case scriptablePlayer(ScriptableMediaPlayer)
    case mediaKey
  }
}
