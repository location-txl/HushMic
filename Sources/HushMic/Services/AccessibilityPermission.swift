import AppKit
import ApplicationServices

enum AccessibilityPermission {
  static var isTrusted: Bool {
    AXIsProcessTrusted()
  }

  @discardableResult
  static func requestPrompt() -> Bool {
    let options = [
      kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
    ] as CFDictionary

    return AXIsProcessTrustedWithOptions(options)
  }

  static func openSettings() {
    guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
      return
    }

    NSWorkspace.shared.open(url)
  }
}
