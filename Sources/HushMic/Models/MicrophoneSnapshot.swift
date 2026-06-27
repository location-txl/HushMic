import Foundation

struct MicrophoneSnapshot: Equatable {
  var isActive: Bool
  var activeDeviceNames: [String]
  var inputDeviceNames: [String]
  var errorMessage: LocalizedMessage?

  static let unknown = MicrophoneSnapshot(
    isActive: false,
    activeDeviceNames: [],
    inputDeviceNames: [],
    errorMessage: .key("status.initializing")
  )

  func primaryDeviceName(localizer: AppLocalizer) -> String {
    if let activeName = activeDeviceNames.first {
      return activeName
    }

    if let inputName = inputDeviceNames.first {
      return inputName
    }

    return localizer.text("status.no_microphone")
  }
}
