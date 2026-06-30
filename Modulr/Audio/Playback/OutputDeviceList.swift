import Foundation
import CoreAudio

/**
 * OutputDevice
 * Represents one CoreAudio output device — built-in speakers, headphones, AirPlay,
 * Bluetooth, USB, virtual aggregates, etc.
 */
struct OutputDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let name: String
    let transportType: UInt32

    var isAirPlay: Bool { transportType == kAudioDeviceTransportTypeAirPlay }
    var isBluetooth: Bool { transportType == kAudioDeviceTransportTypeBluetooth }
    var isHeadphones: Bool {
        // Heuristic: built-in headphones report kAudioDeviceTransportTypeBuiltIn
        // and the user usually distinguishes by name in the menu.
        false
    }

    var iconName: String {
        switch true {
        case isAirPlay: return "airplayaudio"
        case isBluetooth: return "headphones"
        default: return "speaker.wave.2.fill"
        }
    }
}

/**
 * OutputDeviceList
 * Polls CoreAudio for output devices, watches default-output changes, and
 * provides a `setDefault` action that flips the system default output.
 * AudioPlayer's existing default-device listener rebinds engine output afterward.
 */
final class OutputDeviceList: ObservableObject {
    @Published private(set) var devices: [OutputDevice] = []
    @Published private(set) var currentDeviceID: AudioDeviceID?

    init() {
        refresh()
        installListener()
    }

    func refresh() {
        devices = Self.fetchOutputDevices()
        currentDeviceID = Self.defaultOutputDeviceID()
    }

    static func setDefault(_ id: AudioDeviceID) {
        var deviceID = id
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, size, &deviceID
        )
        if status != noErr {
            print("OutputDeviceList: setDefault failed status=\(status)")
        }
    }

    private func installListener() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main
        ) { [weak self] _, _ in
            self?.refresh()
        }

        var defaultAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultAddr,
            DispatchQueue.main
        ) { [weak self] _, _ in
            self?.currentDeviceID = Self.defaultOutputDeviceID()
        }
    }

    // CoreAudio queries

    private static func defaultOutputDeviceID() -> AudioDeviceID? {
        var id: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size, &id
        )
        return status == noErr && id != 0 ? id : nil
    }

    private static func fetchOutputDevices() -> [OutputDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size
        ) == noErr else { return [] }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size, &ids
        ) == noErr else { return [] }

        return ids.compactMap(Self.describeIfOutput)
    }

    private static func describeIfOutput(_ id: AudioDeviceID) -> OutputDevice? {
        guard hasOutputStreams(id), !isHidden(id), !isSoftwareTransport(id) else { return nil }
        let name = deviceName(id) ?? "Unknown"
        return OutputDevice(id: id, name: name, transportType: transportType(id))
    }

    /// Skip devices CoreAudio marks as hidden (HAL plugins, helper aggregates).
    private static func isHidden(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyIsHidden,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else {
            return false
        }
        return value != 0
    }

    /// Drop pure-software transports (aggregates, virtual drivers, unknown).
    /// All real hardware + AirPlay surface naturally.
    private static func isSoftwareTransport(_ id: AudioDeviceID) -> Bool {
        let t = transportType(id)
        return t == kAudioDeviceTransportTypeAggregate
            || t == kAudioDeviceTransportTypeAutoAggregate
            || t == kAudioDeviceTransportTypeVirtual
            || t == kAudioDeviceTransportTypeUnknown
    }

    private static func hasOutputStreams(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr,
              size > 0 else { return false }
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 1)
        defer { buffer.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, buffer) == noErr else {
            return false
        }
        let list = buffer.assumingMemoryBound(to: AudioBufferList.self)
        let bufferList = UnsafeMutableAudioBufferListPointer(list)
        return bufferList.contains(where: { $0.mNumberChannels > 0 })
    }

    private static func deviceName(_ id: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<CFString?>.size)
        var cfName: Unmanaged<CFString>?
        let status = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &cfName)
        guard status == noErr, let value = cfName?.takeRetainedValue() else { return nil }
        return value as String
    }

    private static func transportType(_ id: AudioDeviceID) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value)
        return value
    }
}
