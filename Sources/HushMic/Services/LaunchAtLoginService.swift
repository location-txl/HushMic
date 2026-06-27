import Foundation
import ServiceManagement

enum LaunchAtLoginService {
  static var isEnabled: Bool {
    SMAppService.mainApp.status == .enabled
  }

  static func setEnabled(_ enabled: Bool) -> LocalizedMessage? {
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
    } catch {
      return .raw(error.localizedDescription)
    }

    switch SMAppService.mainApp.status {
    case .enabled:
      return enabled ? nil : .key("login.still_enabled")
    case .notRegistered:
      return enabled ? .key("login.not_registered") : nil
    case .requiresApproval:
      return .key("login.requires_approval")
    case .notFound:
      return .key("login.not_found")
    @unknown default:
      return .key("login.unknown_status")
    }
  }
}
