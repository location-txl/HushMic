import CoreAudio
import Foundation

enum CoreAudioDeviceQuery {
  static let systemObject = AudioObjectID(kAudioObjectSystemObject)

  static func inputDevices() throws -> [AudioDeviceID] {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDevices,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )

    var dataSize: UInt32 = 0
    try check(AudioObjectGetPropertyDataSize(systemObject, &address, 0, nil, &dataSize), context: .key("coreaudio.read_device_list_size"))

    let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
    guard count > 0 else {
      return []
    }

    var devices = [AudioDeviceID](repeating: 0, count: count)
    try check(AudioObjectGetPropertyData(systemObject, &address, 0, nil, &dataSize, &devices), context: .key("coreaudio.read_device_list"))

    return devices.filter { device in
      (try? inputChannelCount(for: device)) ?? 0 > 0
    }
  }

  static func isInputDeviceRunning(_ device: AudioDeviceID) -> Bool {
    isDeviceRunningSomewhere(device, scope: kAudioDevicePropertyScopeInput)
      || isDeviceRunningSomewhere(device, scope: kAudioObjectPropertyScopeGlobal)
  }

  static func activeInputDeviceIDs() throws -> [AudioDeviceID] {
    let activeProcessDevices = try processObjectIDs()
      .filter(isProcessRunningInput)
      .flatMap { try processDevices($0, scope: kAudioObjectPropertyScopeInput) }

    if !activeProcessDevices.isEmpty {
      return Array(Set(activeProcessDevices))
    }

    return try inputDevices().filter(isInputDeviceRunning)
  }

  static func isOutputRunning(forBundleIdentifier bundleIdentifier: String) -> Bool {
    (try? processObjectIDs().contains { process in
      processBundleIdentifier(process) == bundleIdentifier && isProcessRunningOutput(process)
    }) ?? false
  }

  static func deviceName(_ device: AudioDeviceID) -> String {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioObjectPropertyName,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var dataSize = UInt32(MemoryLayout<CFString?>.size)
    let nameStorage = UnsafeMutableRawPointer.allocate(
      byteCount: Int(dataSize),
      alignment: MemoryLayout<CFString?>.alignment
    )
    let namePointer = nameStorage.bindMemory(to: CFString?.self, capacity: 1)
    namePointer.initialize(to: nil)
    defer {
      namePointer.deinitialize(count: 1)
      nameStorage.deallocate()
    }

    let status = AudioObjectGetPropertyData(device, &address, 0, nil, &dataSize, nameStorage)
    guard status == noErr, let name = namePointer.pointee else {
      return String(localized: "device.fallback_name \(device)")
    }

    return name as String
  }

  static func runningAddress() -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
      mScope: kAudioDevicePropertyScopeInput,
      mElement: kAudioObjectPropertyElementMain
    )
  }

  static func devicesAddress() -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDevices,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
  }

  static func processListAddress() -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyProcessObjectList,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
  }

  private static func processObjectIDs() throws -> [AudioObjectID] {
    var address = processListAddress()
    return try objectIDs(for: systemObject, address: &address, context: .key("coreaudio.read_process_list"))
  }

  private static func processDevices(_ process: AudioObjectID, scope: AudioObjectPropertyScope) throws -> [AudioDeviceID] {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioProcessPropertyDevices,
      mScope: scope,
      mElement: kAudioObjectPropertyElementMain
    )
    return try objectIDs(for: process, address: &address, context: .key("coreaudio.read_process_devices"))
  }

  private static func objectIDs(
    for objectID: AudioObjectID,
    address: inout AudioObjectPropertyAddress,
    context: LocalizedMessage
  ) throws -> [AudioObjectID] {
    var dataSize: UInt32 = 0
    try check(AudioObjectGetPropertyDataSize(objectID, &address, 0, nil, &dataSize), context: .key("coreaudio.context_size %@", [context]))

    let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
    guard count > 0 else {
      return []
    }

    var objectIDs = [AudioObjectID](repeating: 0, count: count)
    try check(AudioObjectGetPropertyData(objectID, &address, 0, nil, &dataSize, &objectIDs), context: context)
    return objectIDs
  }

  private static func isProcessRunningInput(_ process: AudioObjectID) -> Bool {
    processFlag(process, selector: kAudioProcessPropertyIsRunningInput)
  }

  private static func isProcessRunningOutput(_ process: AudioObjectID) -> Bool {
    processFlag(process, selector: kAudioProcessPropertyIsRunningOutput)
  }

  private static func processBundleIdentifier(_ process: AudioObjectID) -> String? {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioProcessPropertyBundleID,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var dataSize = UInt32(MemoryLayout<CFString?>.size)
    let bundleIDStorage = UnsafeMutableRawPointer.allocate(
      byteCount: Int(dataSize),
      alignment: MemoryLayout<CFString?>.alignment
    )
    let bundleIDPointer = bundleIDStorage.bindMemory(to: CFString?.self, capacity: 1)
    bundleIDPointer.initialize(to: nil)
    defer {
      bundleIDPointer.deinitialize(count: 1)
      bundleIDStorage.deallocate()
    }

    let status = AudioObjectGetPropertyData(process, &address, 0, nil, &dataSize, bundleIDStorage)
    guard status == noErr, let bundleIdentifier = bundleIDPointer.pointee else {
      return nil
    }

    return bundleIdentifier as String
  }

  private static func processFlag(_ process: AudioObjectID, selector: AudioObjectPropertySelector) -> Bool {
    var address = AudioObjectPropertyAddress(
      mSelector: selector,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var value: UInt32 = 0
    var dataSize = UInt32(MemoryLayout<UInt32>.size)

    let status = AudioObjectGetPropertyData(process, &address, 0, nil, &dataSize, &value)
    return status == noErr && value != 0
  }

  private static func isDeviceRunningSomewhere(_ device: AudioDeviceID, scope: AudioObjectPropertyScope) -> Bool {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
      mScope: scope,
      mElement: kAudioObjectPropertyElementMain
    )
    var value: UInt32 = 0
    var dataSize = UInt32(MemoryLayout<UInt32>.size)

    let status = AudioObjectGetPropertyData(device, &address, 0, nil, &dataSize, &value)
    return status == noErr && value != 0
  }

  private static func inputChannelCount(for device: AudioDeviceID) throws -> UInt32 {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyStreamConfiguration,
      mScope: kAudioDevicePropertyScopeInput,
      mElement: kAudioObjectPropertyElementMain
    )

    var dataSize: UInt32 = 0
    let sizeStatus = AudioObjectGetPropertyDataSize(device, &address, 0, nil, &dataSize)
    guard sizeStatus == noErr, dataSize > 0 else {
      return 0
    }

    let buffer = UnsafeMutableRawPointer.allocate(
      byteCount: Int(dataSize),
      alignment: MemoryLayout<AudioBufferList>.alignment
    )
    defer { buffer.deallocate() }

    let audioBufferList = buffer.bindMemory(to: AudioBufferList.self, capacity: 1)
    try check(AudioObjectGetPropertyData(device, &address, 0, nil, &dataSize, audioBufferList), context: .key("coreaudio.read_input_channels"))

    return UnsafeMutableAudioBufferListPointer(audioBufferList).reduce(0) { total, audioBuffer in
      total + audioBuffer.mNumberChannels
    }
  }

  private static func check(_ status: OSStatus, context: LocalizedMessage) throws {
    guard status == noErr else {
      throw CoreAudioError(context: context, status: status)
    }
  }
}

struct CoreAudioError: Error, LocalizedError {
  var context: LocalizedMessage
  var status: OSStatus

  var localizedMessage: LocalizedMessage {
    .coreAudioError(context, status)
  }

  var errorDescription: String? {
    localizedMessage.resolve(with: AppLocalizer())
  }
}
