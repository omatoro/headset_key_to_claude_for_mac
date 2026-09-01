import Foundation

/// アプリ設定(UserDefaults)。
/// 上流にあったメディア転送先・上流アップデート関連の設定は機構ごと撤去済み。
class AppConfiguration {
    static let shared = AppConfiguration()

    private let useHeadsetMicKey = "UseHeadsetMic"
    private let debugLoggingEnabledKey = "DebugLoggingEnabled"

    private init() {}

    // MARK: - 集音マイクの選択(ヘッドセットで話すか)

    /// true(デフォルト): ヘッドセットのマイクで話す(録音中はボタンが効かない)。
    /// false: Mac側マイクで話す(録音中もボタンで停止・送信できる)。
    func useHeadsetMic() -> Bool {
        UserDefaults.standard.object(forKey: useHeadsetMicKey) as? Bool ?? true
    }

    func setUseHeadsetMic(_ use: Bool) {
        UserDefaults.standard.set(use, forKey: useHeadsetMicKey)
    }

    // MARK: - Debug Logging

    func isDebugLoggingEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: debugLoggingEnabledKey)
    }

    func setDebugLoggingEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: debugLoggingEnabledKey)
    }
}
