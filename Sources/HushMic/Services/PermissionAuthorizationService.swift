import AppKit
import CoreServices
import Foundation
import MediaPlayer

enum AppPermissionRequirement: Equatable {
  case accessibility
  case mediaLibrary
  case automation(ScriptableMediaPlayer)

  func title(localizer: AppLocalizer) -> String {
    switch self {
    case .accessibility:
      return localizer.text("permission.accessibility")
    case .mediaLibrary:
      return localizer.text("permission.media_library")
    case .automation(let player):
      return localizer.text("permission.automation %@", player.displayName)
    }
  }
}

final class PermissionAuthorizationService {
  func missingPermissions() -> [AppPermissionRequirement] {
    var permissions: [AppPermissionRequirement] = []

    if !AccessibilityPermission.isTrusted {
      permissions.append(.accessibility)
    }

    if MPMediaLibrary.authorizationStatus() != .authorized {
      permissions.append(.mediaLibrary)
    }

    permissions += Self.runningPlayersNeedingAutomationPermission().map {
      .automation($0)
    }

    return permissions
  }

  func isGranted(_ permission: AppPermissionRequirement) -> Bool {
    switch permission {
    case .accessibility:
      return AccessibilityPermission.isTrusted
    case .mediaLibrary:
      return MPMediaLibrary.authorizationStatus() == .authorized
    case .automation(let player):
      return Self.hasAutomationPermission(for: player)
    }
  }

  static func requestMediaLibraryPermission(
    completion: @escaping (MPMediaLibraryAuthorizationStatus) -> Void
  ) {
    MPMediaLibrary.requestAuthorization(completion)
  }

  static func runningPlayersNeedingAutomationPermission() -> [ScriptableMediaPlayer] {
    ScriptableMediaPlayer.supportedPlayers.filter { player in
      player.isRunning && !hasAutomationPermission(for: player)
    }
  }

  static func hasAutomationPermission(for player: ScriptableMediaPlayer) -> Bool {
    automationPermissionStatus(for: player, askUserIfNeeded: false) == noErr
  }

  @discardableResult
  static func requestAutomationPermission(for player: ScriptableMediaPlayer) -> Bool {
    automationPermissionStatus(for: player, askUserIfNeeded: true) == noErr
  }

  private static func automationPermissionStatus(
    for player: ScriptableMediaPlayer,
    askUserIfNeeded: Bool
  ) -> OSStatus {
    guard player.isRunning else {
      return OSStatus(procNotFound)
    }

    let descriptor = NSAppleEventDescriptor(bundleIdentifier: player.bundleIdentifier)
    guard let target = descriptor.aeDesc else {
      return OSStatus(errAEEventNotPermitted)
    }

    return AEDeterminePermissionToAutomateTarget(
      target,
      typeWildCard,
      typeWildCard,
      askUserIfNeeded
    )
  }
}
