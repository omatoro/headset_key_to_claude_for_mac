import Cocoa
import ApplicationServices

/// Claude Desktopの現在会話のマイク/送信ボタンをアクセシビリティAPIで操作する。
///
/// 状態はアプリ内に持たない(状態読取型トグル): 発火のたびにAXツリーを読み、
/// 送信ボタンが見えていれば「録音中→送信」、見えていなければ「マイク→録音開始」を押す。
/// 外部でマウス操作された場合でも実UIと食い違わない。
class ClaudeVoiceTrigger {
    static let claudeBundleId = "com.anthropic.claudefordesktop"

    // MARK: 実測確定の特定子(2026-09-01・日本語UI)
    // 非録音時: マイク = AXCheckBox desc「長押しして録音」(録音中は desc が「音声入力を停止」に変わる)
    // 録音中:   送信 = AXButton desc「送信」が出現
    // desc は完全一致で比較する。部分一致だと常設の「フィードバックを送信」ボタンに誤爆するため。
    // Claude DesktopのUI言語や文言が変わったら、SIGUSR1のdumpで再採取してここを更新する。
    static let micRole = "AXCheckBox"
    static let micDesc = "長押しして録音"
    static let micStopDesc = "音声入力を停止"
    static let sendRole = "AXButton"
    static let sendDesc = "送信"

    /// マイクボタン(非録音/録音中のどちらのdescでも同一要素)を厳密に特定する。
    /// role一致だけで拾うと無関係のAXCheckBox(実測: 「リモートコントロール」)を誤爆する。
    private func findMic(in buttons: [AXButtonInfo]) -> AXButtonInfo? {
        buttons.first { $0.role == Self.micRole && ($0.desc == Self.micDesc || $0.desc == Self.micStopDesc) }
    }

    struct AXButtonInfo {
        let element: AXUIElement
        let role: String
        let desc: String
        let enabled: Bool
        let line: String
    }

    init() {
        // AXManualAccessibilityは設定から反映まで数秒かかる(実測)。発火時に間に合うよう、
        // 常駐開始時とClaude Desktop起動時に先行設定しておく。
        primeAccessibility()
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == Self.claudeBundleId else { return }
            debugLog("ClaudeVoiceTrigger: Claude Desktop launched — priming accessibility")
            self?.primeAccessibility()
        }
    }

    private func primeAccessibility() {
        _ = claudeAXApp()
    }

    // MARK: - Claudeアプリの解決

    private func claudeAXApp() -> AXUIElement? {
        guard let app = NSRunningApplication
            .runningApplications(withBundleIdentifier: Self.claudeBundleId).first else {
            debugLog("ClaudeVoiceTrigger: Claude Desktop is not running")
            return nil
        }
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        // Electronはこの属性を立てるまでweb contentsをAXツリーへ出さない
        AXUIElementSetAttributeValue(ax, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        return ax
    }

    func isClaudeFrontmost() -> Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Self.claudeBundleId
    }

    // MARK: - AX属性ヘルパ

    private func copyString(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private func copyChildren(_ element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
              let children = value as? [AXUIElement] else {
            return []
        }
        return children
    }

    private static let interactiveRoles: Set<String> = [
        "AXButton", "AXCheckBox", "AXPopUpButton", "AXMenuButton", "AXRadioButton", "AXToggle"
    ]

    /// ウィンドウ以下を再帰走査してインタラクティブ要素を収集する
    private func collectButtons() -> [AXButtonInfo] {
        guard let app = claudeAXApp() else { return [] }
        var windows: CFTypeRef?
        let werr = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windows)
        guard werr == .success, let winList = windows as? [AXUIElement], !winList.isEmpty else {
            debugLog("ClaudeVoiceTrigger: no AX windows (error=\(werr.rawValue))")
            return []
        }
        var found: [AXButtonInfo] = []
        var visited = 0
        for window in winList {
            walk(window, depth: 0, visited: &visited, found: &found)
        }
        debugLog("ClaudeVoiceTrigger: AX walk visited=\(visited) buttons=\(found.count)")
        return found
    }

    private func walk(_ element: AXUIElement, depth: Int,
                      visited: inout Int, found: inout [AXButtonInfo]) {
        if depth > 60 || visited > 12000 { return }
        visited += 1
        let role = copyString(element, kAXRoleAttribute as String) ?? "?"
        if Self.interactiveRoles.contains(role) {
            let desc = copyString(element, kAXDescriptionAttribute as String) ?? ""
            var enabledRef: CFTypeRef?
            var enabled = true
            if AXUIElementCopyAttributeValue(element, kAXEnabledAttribute as CFString, &enabledRef) == .success,
               let b = enabledRef as? Bool {
                enabled = b
            }
            var parts = ["role=\(role)"]
            if let t = copyString(element, kAXTitleAttribute as String), !t.isEmpty { parts.append("title=\(t)") }
            if !desc.isEmpty { parts.append("desc=\(desc)") }
            if let h = copyString(element, kAXHelpAttribute as String), !h.isEmpty { parts.append("help=\(h)") }
            if let i = copyString(element, kAXIdentifierAttribute as String), !i.isEmpty { parts.append("id=\(i)") }
            if !enabled { parts.append("disabled") }
            found.append(AXButtonInfo(element: element, role: role, desc: desc, enabled: enabled,
                                      line: parts.joined(separator: " | ")))
        }
        for child in copyChildren(element) {
            walk(child, depth: depth + 1, visited: &visited, found: &found)
        }
    }

    // MARK: - dump (SIGUSR1)

    /// Claude Desktopの全インタラクティブ要素をログへ出す(特定子の再採取用)
    func dumpAccessibilityTree(retryOnEmpty: Bool = true) {
        debugLog("AXdump: begin (frontmost=\(isClaudeFrontmost()))")
        let buttons = collectButtons()
        if buttons.isEmpty, retryOnEmpty {
            debugLog("AXdump: empty — retry in 1s")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.dumpAccessibilityTree(retryOnEmpty: false)
            }
            return
        }
        for (index, button) in buttons.enumerated() {
            debugLog("AXdump[\(index)]: \(button.line)")
            // 音声入力系のボタンは、持っているAXアクションと画面上の位置も出す
            // (単発AXPressで録音が始まらなかったため、代替操作手段の調査用)
            let isVoiceUI = (button.role == Self.micRole && (button.desc == Self.micDesc || button.desc == "音声入力を停止"))
                || (button.role == Self.sendRole && button.desc == Self.sendDesc)
            if isVoiceUI {
                debugLog("AXdump[\(index)] actions=\(copyActionNames(button.element)) frame=\(frameString(button.element))")
            }
        }
        debugLog("AXdump: end (\(buttons.count) buttons)")
    }

    private func copyActionNames(_ element: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success,
              let list = names as? [String] else { return [] }
        return list
    }

    private func frameString(_ element: AXUIElement) -> String {
        var point = CGPoint.zero
        var size = CGSize.zero
        var posRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
           let pv = posRef, CFGetTypeID(pv) == AXValueGetTypeID() {
            AXValueGetValue(pv as! AXValue, .cgPoint, &point)
        }
        var sizeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
           let sv = sizeRef, CFGetTypeID(sv) == AXValueGetTypeID() {
            AXValueGetValue(sv as! AXValue, .cgSize, &size)
        }
        return "(\(Int(point.x)),\(Int(point.y)) \(Int(size.width))x\(Int(size.height)))"
    }

    // MARK: - fire (ヘッドセットボタン / SIGUSR2)

    /// ボタン操作のフロー:
    ///   押下1 = 録音開始 / 押下2 = 停止(文字起こしが入力欄に入り確認できる) /
    ///   押下3 = 送信 — ただし「入力欄にテキストがある(=送信ボタンが見える)なら押下=送信」の
    ///   一般則であり、手で打ったテキストの送信も同じ動作になる。
    ///
    /// 内部で覚えるのは「録音を自分で開始したか」(recording)と「停止を押した時刻」だけ。
    /// ElectronのAXツリーは実UIより数秒遅れる実測があるため、停止直後の押下では
    /// 送信ボタンの出現をリトライで待つ(それ以外の押下は遅延ゼロで即動作)。
    private var isRecordingByUs = false
    private var lastStopAt = Date.distantPast
    private var sendInFlight = false

    /// 「録音を自分で開始した」ヒントを使うか。ヘッドセットのマイクで話すモードでは
    /// 録音中のボタンイベント自体が届かない(通話モード切替)ため、押下が来た時点で
    /// 録音は外部(マウス)操作で終わっている。ヒントを使うと実UIとズレて誤動作する
    /// (実測: マウス停止後の押下が停止扱いになり再録音が始まった)ので、
    /// そのモードでは実UI(desc)だけで判定する。AppDelegateがモードに応じて設定する。
    var useRecordingHint = true
    /// 停止からこの時間内の押下は「送信ボタンの出現待ち」をする(文字起こし反映+AX遅延の吸収)
    private static let stopToSendWindow: TimeInterval = 15.0

    /// トリガー本体。Claudeが最前面の時のみ動く。
    func fire() {
        guard isClaudeFrontmost() else {
            debugLog("ClaudeVoiceTrigger: fire ignored — Claude Desktop is not frontmost")
            return
        }
        if sendInFlight {
            debugLog("ClaudeVoiceTrigger: fire ignored — send already in flight")
            return
        }
        let buttons = collectButtons()
        let mic = findMic(in: buttons)

        // 1. 録音中(自分で開始した or 実UIのマイクが「音声入力を停止」表示) → 停止
        if (useRecordingHint && isRecordingByUs) || mic?.desc == Self.micStopDesc {
            guard let mic = mic else {
                debugLog("ClaudeVoiceTrigger: recording but mic button not found")
                isRecordingByUs = false
                return
            }
            press(mic.element, label: "mic(stop)")
            isRecordingByUs = false
            lastStopAt = Date()
            return
        }

        // 2. 送信ボタンが見えている(入力欄にテキストあり) → 送信
        // 「送信」ボタン要素は入力欄が空でもUIに常在しうるため、押せる状態(enabled)の時だけ
        // 「テキストあり」とみなす(空欄時の押下が送信残像に吸われて無反応になった実測への対策)
        if let send = buttons.first(where: { $0.role == Self.sendRole && $0.desc == Self.sendDesc && $0.enabled }) {
            press(send.element, label: "send")
            return
        }

        // 2'. 停止直後は文字起こし反映とAXツリー遅延で送信ボタンがまだ見えないことがある
        //     → 出現をリトライで待って送信(見つからなければ何もしない)
        if Date().timeIntervalSince(lastStopAt) < Self.stopToSendWindow {
            sendInFlight = true
            attemptSend(retriesLeft: 6)
            return
        }

        // 3. それ以外 → 録音開始
        guard let mic = mic else {
            debugLog("ClaudeVoiceTrigger: no mic button found (buttons=\(buttons.count))")
            return
        }
        press(mic.element, label: "mic(start)")
        isRecordingByUs = true
        verifyAfterPress(expectRecording: true)
    }

    /// 送信ボタンの出現待ちリトライ。枯渇時(文字起こしが空等)は何も押さない。
    private func attemptSend(retriesLeft: Int) {
        let buttons = collectButtons()
        if let send = buttons.first(where: { $0.role == Self.sendRole && $0.desc == Self.sendDesc && $0.enabled }) {
            press(send.element, label: "send(after-stop)")
            sendInFlight = false
            lastStopAt = .distantPast
            return
        }
        if retriesLeft > 0 {
            debugLog("ClaudeVoiceTrigger: send button not visible yet — retry (\(retriesLeft) left)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.attemptSend(retriesLeft: retriesLeft - 1)
            }
            return
        }
        debugLog("ClaudeVoiceTrigger: send retry exhausted — nothing to send (empty transcript?)")
        sendInFlight = false
    }

    private func press(_ element: AXUIElement, label: String) {
        let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
        debugLog("ClaudeVoiceTrigger: AXPress [\(label)] → \(result == .success ? "success" : "error \(result.rawValue)")")
    }

    /// 押下後にAXを再読取し、録音UI(送信ボタン)の有無をログへ残す。
    /// ElectronのAXツリー反映は実UIより数秒遅れるため2秒待つ(0.5秒では偽陰性だった実測)。
    /// このログは診断用の参考情報であり、falseでも実UIでは録音が始まっていることがある。
    private func verifyAfterPress(expectRecording: Bool) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self = self else { return }
            let buttons = self.collectButtons()
            let recording = buttons.contains { $0.role == Self.sendRole && $0.desc == Self.sendDesc }
            debugLog("ClaudeVoiceTrigger: post-press recordingUI=\(recording) (expected=\(expectRecording))")
        }
    }
}
