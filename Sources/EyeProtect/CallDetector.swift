import CoreMediaIO
import CoreAudio

/// Detects whether the camera or microphone is currently in use by *any* app.
/// This is the primary "am I in a meeting" signal — and the only thing that
/// catches browser-based calls like Google Meet (a Chrome tab, not an app).
///
/// Reads the public "is running somewhere" device property; querying it does not
/// open the device, so it requires no camera/mic permission.
struct CallDetector {
    var isCameraInUse: Bool { Self.cameraRunningSomewhere() }
    var isMicInUse: Bool { Self.micRunningSomewhere() }
    var inCall: Bool { isCameraInUse || isMicInUse }

    // MARK: - Camera (CoreMediaIO)

    private static func cameraRunningSomewhere() -> Bool {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))

        var dataSize: UInt32 = 0
        let sys = CMIOObjectID(kCMIOObjectSystemObject)
        guard CMIOObjectGetPropertyDataSize(sys, &address, 0, nil, &dataSize) == OSStatus(kCMIOHardwareNoError),
              dataSize > 0 else { return false }

        let count = Int(dataSize) / MemoryLayout<CMIOObjectID>.size
        var devices = [CMIOObjectID](repeating: 0, count: count)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(sys, &address, 0, nil, dataSize, &used, &devices) == OSStatus(kCMIOHardwareNoError)
        else { return false }

        for device in devices where device != 0 {
            var runAddr = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard))
            var running: UInt32 = 0
            var outUsed: UInt32 = 0
            let size = UInt32(MemoryLayout<UInt32>.size)
            if CMIOObjectGetPropertyData(device, &runAddr, 0, nil, size, &outUsed, &running) == OSStatus(kCMIOHardwareNoError),
               running != 0 {
                return true
            }
        }
        return false
    }

    // MARK: - Microphone (CoreAudio)

    private static func micRunningSomewhere() -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)

        var dataSize: UInt32 = 0
        let sys = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(sys, &address, 0, nil, &dataSize) == noErr, dataSize > 0 else { return false }

        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var devices = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(sys, &address, 0, nil, &dataSize, &devices) == noErr else { return false }

        for device in devices where device != 0 {
            guard deviceHasInput(device) else { continue }
            var runAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
            var running: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(device, &runAddr, 0, nil, &size, &running) == noErr, running != 0 {
                return true
            }
        }
        return false
    }

    private static func deviceHasInput(_ device: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size > 0 else { return false }

        let bufferList = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { bufferList.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, bufferList) == noErr else { return false }

        let abl = UnsafeMutableAudioBufferListPointer(
            bufferList.assumingMemoryBound(to: AudioBufferList.self))
        var channels = 0
        for buffer in abl { channels += Int(buffer.mNumberChannels) }
        return channels > 0
    }
}
