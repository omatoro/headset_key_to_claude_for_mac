import Foundation
import CoreAudio

/// システムのデフォルト入力デバイス(集音マイク)の制御。
///
/// 「ヘッドセットで話す」OFFのとき、集音を非Bluetoothマイク(Mac側)へ固定する。
/// Bluetoothヘッドセットのマイクで集音すると本体が通話モードへ切替わり、
/// 録音中はボタンのメディアイベントが届かなくなる(実測)ため。
class AudioInputSwitcher {
    static let shared = AudioInputSwitcher()

    private var enforcing = false
    private var listenerBlock: AudioObjectPropertyListenerBlock?

    private func address(_ selector: AudioObjectPropertySelector,
                         scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    // MARK: - CoreAudio 読み取り

    private func defaultInputDevice() -> AudioDeviceID? {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = address(kAudioHardwarePropertyDefaultInputDevice)
        let err = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &device)
        return err == noErr && device != 0 ? device : nil
    }

    private func allDevices() -> [AudioDeviceID] {
        var addr = address(kAudioHardwarePropertyDevices)
        var size = UInt32(0)
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else {
            return []
        }
        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &devices) == noErr else {
            return []
        }
        return devices
    }

    private func hasInput(_ device: AudioDeviceID) -> Bool {
        var addr = address(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeInput)
        var size = UInt32(0)
        guard AudioObjectGetPropertyDataSize(device, &addr, 0, nil, &size) == noErr else { return false }
        return size > 0
    }

    private func transportType(of device: AudioDeviceID) -> UInt32 {
        var addr = address(kAudioDevicePropertyTransportType)
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value) == noErr else { return 0 }
        return value
    }

    private func isBluetooth(_ device: AudioDeviceID) -> Bool {
        let t = transportType(of: device)
        return t == kAudioDeviceTransportTypeBluetooth || t == kAudioDeviceTransportTypeBluetoothLE
    }

    private func name(of device: AudioDeviceID) -> String {
        var addr = address(kAudioObjectPropertyName)
        var value: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let err = withUnsafeMutablePointer(to: &value) { ptr -> OSStatus in
            AudioObjectGetPropertyData(device, &addr, 0, nil, &size, ptr)
        }
        return err == noErr ? (value as String) : "device \(device)"
    }

    func isDefaultInputBluetooth() -> Bool {
        guard let device = defaultInputDevice() else { return false }
        return isBluetooth(device)
    }

    // MARK: - 切り替え

    private func setDefaultInput(_ device: AudioDeviceID) -> Bool {
        var addr = address(kAudioHardwarePropertyDefaultInputDevice)
        var target = device
        let err = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil,
                                            UInt32(MemoryLayout<AudioDeviceID>.size), &target)
        return err == noErr
    }

    /// 非Bluetoothの入力デバイスへ切り替える(内蔵を優先)。成功時true。
    @discardableResult
    func switchToNonBluetoothInput() -> Bool {
        let candidates = allDevices().filter { hasInput($0) && !isBluetooth($0) }
        guard !candidates.isEmpty else {
            debugLog("AudioInput: no non-Bluetooth input device found")
            return false
        }
        let builtIn = candidates.first { transportType(of: $0) == kAudioDeviceTransportTypeBuiltIn }
        let target = builtIn ?? candidates[0]
        if defaultInputDevice() == target { return true }
        let ok = setDefaultInput(target)
        debugLog("AudioInput: default input → \(name(of: target)) (\(ok ? "ok" : "failed"))")
        return ok
    }

    /// Bluetoothの入力デバイス(ヘッドセット)へ切り替える。無ければ何もしない。
    @discardableResult
    func switchToBluetoothInput() -> Bool {
        guard let target = allDevices().first(where: { hasInput($0) && isBluetooth($0) }) else {
            debugLog("AudioInput: no Bluetooth input device found (nothing to switch)")
            return false
        }
        if defaultInputDevice() == target { return true }
        let ok = setDefaultInput(target)
        debugLog("AudioInput: default input → \(name(of: target)) (\(ok ? "ok" : "failed"))")
        return ok
    }

    // MARK: - OFFモード中の自動押し戻し
    // ヘッドセットの再接続等でmacOSがデフォルト入力をBluetoothへ自動変更することがある。
    // 「ヘッドセットで話す」OFFの間はデフォルト入力の変化を監視し、非Bluetoothへ押し戻す。

    func startEnforcingNonBluetooth() {
        switchToNonBluetoothInput()
        guard !enforcing else { return }
        enforcing = true
        var addr = address(kAudioHardwarePropertyDefaultInputDevice)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self = self, self.enforcing else { return }
            if self.isDefaultInputBluetooth() {
                debugLog("AudioInput: default input drifted to Bluetooth — enforcing non-Bluetooth")
                self.switchToNonBluetoothInput()
            }
        }
        listenerBlock = block
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main, block)
        debugLog("AudioInput: enforcement ON (Mac-side mic)")
    }

    func stopEnforcing() {
        guard enforcing, let block = listenerBlock else { enforcing = false; return }
        enforcing = false
        var addr = address(kAudioHardwarePropertyDefaultInputDevice)
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main, block)
        listenerBlock = nil
        debugLog("AudioInput: enforcement OFF")
    }
}
