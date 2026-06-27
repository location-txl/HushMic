import AppKit

final class MediaKeyPlaybackController {
  private let playPauseKeyCode = 16
  private let auxControlButtonSubtype = Int16(8)

  @discardableResult
  func sendPlayPause() -> Bool {
    guard postPlayPause(keyDown: true) else {
      return false
    }

    usleep(10_000)
    return postPlayPause(keyDown: false)
  }

  private func postPlayPause(keyDown: Bool) -> Bool {
    let keyState = keyDown ? 0xA : 0xB
    let data1 = (playPauseKeyCode << 16) | (keyState << 8)

    guard let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(keyState << 8)),
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            subtype: auxControlButtonSubtype,
            data1: data1,
            data2: -1
          ),
          let cgEvent = event.cgEvent else {
      return false
    }

    cgEvent.post(tap: CGEventTapLocation.cghidEventTap)
    return true
  }
}
