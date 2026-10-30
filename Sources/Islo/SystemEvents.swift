import AudioToolbox
import CoreAudio
import Foundation
import IOKit.ps

/// Reports changes of the output volume and mute, following the current output device.
final class VolumeWatcher {
    private let onChange: (Float, Bool) -> Void
    private var device = AudioObjectID(kAudioObjectUnknown)
    private var deviceListener: AudioObjectPropertyListenerBlock?
    private var valueListener: AudioObjectPropertyListenerBlock?

    private static var defaultDeviceAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    private static var volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioObjectPropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )
    private static var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioObjectPropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )

    init(onChange: @escaping (Float, Bool) -> Void) {
        self.onChange = onChange
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.attach() }
        deviceListener = listener
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &Self.defaultDeviceAddress, .main, listener)
        attach()
    }

    private func attach() {
        if let valueListener, device != kAudioObjectUnknown {
            AudioObjectRemovePropertyListenerBlock(device, &Self.volumeAddress, .main, valueListener)
            AudioObjectRemovePropertyListenerBlock(device, &Self.muteAddress, .main, valueListener)
        }
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &Self.defaultDeviceAddress, 0, nil, &size, &device)

        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.report() }
        valueListener = listener
        AudioObjectAddPropertyListenerBlock(device, &Self.volumeAddress, .main, listener)
        AudioObjectAddPropertyListenerBlock(device, &Self.muteAddress, .main, listener)
    }

    private func report() {
        var volume = Float32(0)
        var muted = UInt32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        AudioObjectGetPropertyData(device, &Self.volumeAddress, 0, nil, &size, &volume)
        size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(device, &Self.muteAddress, 0, nil, &size, &muted)
        onChange(volume, muted != 0)
    }
}

/// Reports when the charger is plugged in or removed.
final class PowerWatcher {
    private let onChange: (Int, Bool) -> Void
    private var isCharging: Bool?

    init(onChange: @escaping (Int, Bool) -> Void) {
        self.onChange = onChange
        isCharging = Self.read()?.isCharging
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            Unmanaged<PowerWatcher>.fromOpaque(context).takeUnretainedValue().check()
        }, context)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
    }

    private func check() {
        guard let state = Self.read(), state.isCharging != isCharging else { return }
        isCharging = state.isCharging
        onChange(state.level, state.isCharging)
    }

    static func read() -> (level: Int, isCharging: Bool)? {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  let level = description[kIOPSCurrentCapacityKey] as? Int else { continue }
            let onAC = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            return (level, onAC)
        }
        return nil
    }
}
