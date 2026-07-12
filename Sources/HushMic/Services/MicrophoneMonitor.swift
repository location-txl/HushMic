import CoreAudio
import Foundation

final class MicrophoneMonitor {
  var onChange: ((MicrophoneSnapshot) -> Void)?

  private let queue = DispatchQueue(label: "com.location.HushMic.microphone")
  private var deviceListeners: [RegisteredAudioListener] = []
  private var processListeners: [RegisteredAudioListener] = []
  private var systemListeners: [RegisteredAudioListener] = []
  private var pollTimer: DispatchSourceTimer?
  private var isStarted = false

  deinit {
    stop()
  }

  func start() {
    queue.async { [weak self] in
      guard let self, !self.isStarted else {
        return
      }

      self.isStarted = true
      self.installSystemListeners()
      self.rebuildDeviceListeners()
      self.rebuildProcessListeners()
      self.startPolling()
      self.publishSnapshot()
    }
  }

  func stop() {
    queue.sync {
      pollTimer?.cancel()
      pollTimer = nil
      removeListeners(&deviceListeners)
      removeListeners(&processListeners)
      removeListeners(&systemListeners)
      isStarted = false
    }
  }

  func refresh() {
    queue.async { [weak self] in
      self?.rebuildDeviceListeners()
      self?.rebuildProcessListeners()
      self?.publishSnapshot()
    }
  }

  private func installSystemListeners() {
    var devicesAddress = CoreAudioDeviceQuery.devicesAddress()
    let devicesBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
      self?.rebuildDeviceListeners()
      self?.publishSnapshot()
    }

    let status = AudioObjectAddPropertyListenerBlock(
      CoreAudioDeviceQuery.systemObject,
      &devicesAddress,
      queue,
      devicesBlock
    )

    if status == noErr {
      systemListeners.append(
        RegisteredAudioListener(
          objectID: CoreAudioDeviceQuery.systemObject,
          address: devicesAddress,
          block: devicesBlock
        )
      )
    }

    var processListAddress = CoreAudioDeviceQuery.processListAddress()
    let processListBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
      self?.rebuildProcessListeners()
      self?.publishSnapshot()
    }

    let processStatus = AudioObjectAddPropertyListenerBlock(
      CoreAudioDeviceQuery.systemObject,
      &processListAddress,
      queue,
      processListBlock
    )

    if processStatus == noErr {
      systemListeners.append(
        RegisteredAudioListener(
          objectID: CoreAudioDeviceQuery.systemObject,
          address: processListAddress,
          block: processListBlock
        )
      )
    }
  }

  private func rebuildDeviceListeners() {
    guard isStarted else {
      return
    }

    removeListeners(&deviceListeners)

    guard let devices = try? CoreAudioDeviceQuery.inputDevices() else {
      return
    }

    for device in devices {
      var runningAddress = CoreAudioDeviceQuery.runningAddress()
      let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        self?.publishSnapshot()
      }

      let status = AudioObjectAddPropertyListenerBlock(device, &runningAddress, queue, block)
      guard status == noErr else {
        continue
      }

      deviceListeners.append(
        RegisteredAudioListener(
          objectID: AudioObjectID(device),
          address: runningAddress,
          block: block
        )
      )
    }
  }

  private func rebuildProcessListeners() {
    guard isStarted else {
      return
    }

    removeListeners(&processListeners)

    guard let processes = try? CoreAudioDeviceQuery.processObjectIDs() else {
      return
    }

    for process in processes {
      var inputRunningAddress = CoreAudioDeviceQuery.processInputRunningAddress()
      let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        self?.publishSnapshot()
      }

      let status = AudioObjectAddPropertyListenerBlock(process, &inputRunningAddress, queue, block)
      guard status == noErr else {
        continue
      }

      processListeners.append(
        RegisteredAudioListener(
          objectID: process,
          address: inputRunningAddress,
          block: block
        )
      )
    }
  }

  private func publishSnapshot() {
    do {
      let devices = try CoreAudioDeviceQuery.inputDevices()
      let activeDevices = try CoreAudioDeviceQuery.activeInputDeviceIDs()
      let deviceNames = devices.map(CoreAudioDeviceQuery.deviceName)
      let activeNames = activeDevices.map(CoreAudioDeviceQuery.deviceName)

      onChange?(
        MicrophoneSnapshot(
          isActive: !activeNames.isEmpty,
          activeDeviceNames: activeNames,
          inputDeviceNames: deviceNames,
          errorMessage: nil
        )
      )
    } catch let error as CoreAudioError {
      onChange?(
        MicrophoneSnapshot(
          isActive: false,
          activeDeviceNames: [],
          inputDeviceNames: [],
          errorMessage: error.localizedMessage
        )
      )
    } catch {
      onChange?(
        MicrophoneSnapshot(
          isActive: false,
          activeDeviceNames: [],
          inputDeviceNames: [],
          errorMessage: .raw(error.localizedDescription)
        )
      )
    }
  }

  private func removeListeners(_ listeners: inout [RegisteredAudioListener]) {
    for listener in listeners {
      var address = listener.address
      AudioObjectRemovePropertyListenerBlock(
        listener.objectID,
        &address,
        queue,
        listener.block
      )
    }

    listeners.removeAll()
  }

  private func startPolling() {
    pollTimer?.cancel()

    let timer = DispatchSource.makeTimerSource(queue: queue)
    timer.schedule(deadline: .now() + .milliseconds(250), repeating: .milliseconds(250))
    timer.setEventHandler { [weak self] in
      self?.publishSnapshot()
    }
    pollTimer = timer
    timer.resume()
  }
}

private struct RegisteredAudioListener {
  var objectID: AudioObjectID
  var address: AudioObjectPropertyAddress
  var block: AudioObjectPropertyListenerBlock
}
