import Cocoa

/// Serial queue for log file writes. `debugLog` is called from inside the
/// CGEvent tap callback, which runs on the main run loop — synchronous file
/// I/O there adds latency to event handling, and a slow tap callback is
/// exactly what causes the window server to disable the tap.
private let debugLogQueue = DispatchQueue(label: "com.mediakeys.forwarder.debuglog")

/// Diagnostic logger. In DEBUG builds emits an `NSLog` and appends to
/// `/tmp/macmediakeys.log` (the unified-log filter doesn't always surface our
/// output reliably). Compiles to a no-op in Release.
func debugLog(_ message: String) {
    #if DEBUG
    let enabled = true
    #else
    let enabled = AppConfiguration.shared.isDebugLoggingEnabled()
    #endif
    guard enabled else { return }

    NSLog("MacMediaKeys: \(message)")

    // Timestamp on the calling thread so ordering reflects when the event
    // actually happened, not when the write was drained off the queue.
    let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
    debugLogQueue.async {
        guard let data = line.data(using: .utf8) else { return }
        let path = "/tmp/macmediakeys.log"
        if FileManager.default.fileExists(atPath: path),
           let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, MediaKeyTapDelegate, NowPlayingInterceptorDelegate {
    var statusItem: NSStatusItem?
    var mediaKeyTap: MediaKeyTap!
    var nowPlayingInterceptor: NowPlayingInterceptor!
    var claudeVoiceTrigger: ClaudeVoiceTrigger!
    private var debugSignalSources: [DispatchSourceSignal] = []
    private let config = AppConfiguration.shared

    // Gating: remote-command-center events are only honored if the CGEvent tap
    // saw a real media-key event recently. Otherwise the system can trigger
    // playback via MPRemoteCommandCenter for reasons unrelated to the user
    // pressing a key — notably Bluetooth audio route changes.
    private var lastTapEventTime: Date = .distantPast
    private var cgEventTapActive: Bool = false
    private static let remoteCommandGraceWindow: TimeInterval = 0.5

    // App Nap opt-out. This is a background-only accessory app (LSUIElement),
    // which makes it a prime App Nap candidate — and App Nap coalesces timers
    // aggressively. If our Now Playing refresh timer gets throttled the claim
    // goes stale and macOS resumes routing media keys straight to whichever
    // app is really playing. Held for the process lifetime.
    private var appNapAssertion: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("MacMediaKeys: App launched")

        appNapAssertion = ProcessInfo.processInfo.beginActivity(
            options: .userInitiated,
            reason: "Capturing headset media events requires an unthrottled event tap and Now Playing refresh"
        )

        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = nil
        setupStatusBarIfNeeded()
        rebuildMenu()

        // Setup Now Playing interceptor to claim media key routing from rcd/mediaremoted
        nowPlayingInterceptor = NowPlayingInterceptor()
        nowPlayingInterceptor.delegate = self

        // Claude Desktop音声入力トリガー+デバッグ用シグナル
        // (SIGUSR1=AXツリーdump / SIGUSR2=疑似発火。ターミナルからpkillで叩いて自走検証する)
        claudeVoiceTrigger = ClaudeVoiceTrigger()
        setupDebugSignals()

        // 最前面アプリに連動してNow Playingクレームを切り替える。
        // Claude最前面: クレームON=ヘッドセットのボタンを本アプリが受ける /
        // それ以外: クレームOFF=rcdのルーティングを解放しYouTube等が従来どおり反応する。
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(frontmostAppChanged(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        nowPlayingInterceptor.setClaimActive(claudeVoiceTrigger.isClaudeFrontmost())

        // 集音マイク設定(ヘッドセットで話す/Mac側マイク)を起動時に反映
        applyMicMode()

        // Setup CGEvent media key tap (defer slightly to ensure UI is ready)
        DispatchQueue.main.async { [weak self] in
            self?.setupMediaKeyTap()
        }

        // 改造版: 上流の自動アップデートチェックは行わない。
        // 上流リリースをインストールすると本改造が上書きされるため。
    }

    @objc private func frontmostAppChanged(_ notification: Notification) {
        let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        nowPlayingInterceptor?.setClaimActive(app?.bundleIdentifier == ClaudeVoiceTrigger.claudeBundleId)
    }

    @objc private func selectHeadsetMic() {
        guard !config.useHeadsetMic() else { return }
        config.setUseHeadsetMic(true)
        applyMicMode()
        rebuildMenu()
    }

    @objc private func selectDefaultMic() {
        guard config.useHeadsetMic() else { return }
        config.setUseHeadsetMic(false)
        applyMicMode()
        rebuildMenu()
    }

    /// 「ヘッドセットで話す」設定を集音デバイスとトリガー動作へ反映する。
    private func applyMicMode() {
        let useHeadset = config.useHeadsetMic()
        claudeVoiceTrigger?.useRecordingHint = !useHeadset
        if useHeadset {
            AudioInputSwitcher.shared.stopEnforcing()
            AudioInputSwitcher.shared.switchToBluetoothInput()
            debugLog("MicMode: ヘッドセットで話す=ON (録音中はボタン不可)")
        } else {
            AudioInputSwitcher.shared.startEnforcingNonBluetooth()
            debugLog("MicMode: ヘッドセットで話す=OFF (Mac側マイクで集音)")
        }
    }

    private func setupDebugSignals() {
        signal(SIGUSR1, SIG_IGN)
        signal(SIGUSR2, SIG_IGN)
        let usr1 = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        usr1.setEventHandler { [weak self] in
            debugLog("SIGUSR1 → dumpAccessibilityTree")
            self?.claudeVoiceTrigger.dumpAccessibilityTree()
        }
        usr1.resume()
        let usr2 = DispatchSource.makeSignalSource(signal: SIGUSR2, queue: .main)
        usr2.setEventHandler { [weak self] in
            debugLog("SIGUSR2 → ClaudeVoiceTrigger.fire()")
            self?.claudeVoiceTrigger.fire()
        }
        usr2.resume()
        debugSignalSources = [usr1, usr2]
    }

    private func setupStatusBarIfNeeded() {
        guard statusItem == nil else { return }

        NSLog("MacMediaKeys: Setting up status bar")

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item

        guard let button = item.button else {
            NSLog("MacMediaKeys: ERROR - Failed to get status item button")
            return
        }

        // アプリアイコンと同一モチーフ(ヘッドセット+スパーク)のテンプレート画像。
        // 汎用のヘッドホン記号単体だと別種のユーティリティと紛らわしいため。
        if let url = Bundle.main.url(forResource: "menubar", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            image.isTemplate = true
            image.size = NSSize(width: 20, height: 20)
            image.accessibilityDescription = "headset_key_to_claude_for_mac"
            button.image = image
        } else {
            button.title = "♪"
        }

        NSLog("MacMediaKeys: Status item created, button: \(String(describing: button))")
    }

    func rebuildMenu() {
        let menu = NSMenu()
        // 改造版: メディアキー転送は撤去済みのため、転送先の選択UI
        // (Forward media keys to: / アプリ一覧 / Settings…)は置かない。

        // 集音マイクの選択(2択のラジオ形式・デフォルトはヘッドセットで話す)
        let useHeadset = config.useHeadsetMic()

        let headsetMicItem = NSMenuItem(
            title: "ヘッドセットで話す",
            action: #selector(selectHeadsetMic),
            keyEquivalent: ""
        )
        headsetMicItem.target = self
        headsetMicItem.state = useHeadset ? .on : .off
        menu.addItem(headsetMicItem)

        let headsetNote = NSMenuItem(
            title: "録音中はボタン不可・停止と送信はマウス",
            action: nil, keyEquivalent: ""
        )
        headsetNote.isEnabled = false
        headsetNote.indentationLevel = 1
        menu.addItem(headsetNote)

        let defaultMicItem = NSMenuItem(
            title: "デフォルトマイクで話す",
            action: #selector(selectDefaultMic),
            keyEquivalent: ""
        )
        defaultMicItem.target = self
        defaultMicItem.state = useHeadset ? .off : .on
        menu.addItem(defaultMicItem)

        let defaultNote = NSMenuItem(
            title: "Mac側マイクで集音・開始/停止/送信すべてボタンで完結",
            action: nil, keyEquivalent: ""
        )
        defaultNote.isEnabled = false
        defaultNote.indentationLevel = 1
        menu.addItem(defaultNote)

        menu.addItem(NSMenuItem.separator())

        // Status item
        let statusMenuItem = NSMenuItem(title: "Status: Initializing...", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        statusMenuItem.tag = 100
        menu.addItem(statusMenuItem)

        menu.addItem(NSMenuItem.separator())

        // Accessibility settings
        let accessibilityItem = NSMenuItem(
            title: "Open Accessibility Settings...",
            action: #selector(openAccessibilitySettings),
            keyEquivalent: ""
        )
        accessibilityItem.target = self
        menu.addItem(accessibilityItem)

        // Debug logging(旧Settings画面の廃止に伴いメニューへ移設。他の旧設定は転送/更新の残骸のため撤去)
        let debugLogItem = NSMenuItem(
            title: "Enable Debug Logging",
            action: #selector(toggleDebugLogging),
            keyEquivalent: ""
        )
        debugLogItem.target = self
        debugLogItem.state = config.isDebugLoggingEnabled() ? .on : .off
        menu.addItem(debugLogItem)

        // Debug info
        let debugItem = NSMenuItem(
            title: "Copy Debug Info",
            action: #selector(copyDebugInfo(_:)),
            keyEquivalent: ""
        )
        debugItem.target = self
        menu.addItem(debugItem)

        menu.addItem(NSMenuItem.separator())

        // About
        let aboutItem = NSMenuItem(
            title: "About headset_key_to_claude_for_mac",
            action: #selector(openAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(
            title: "Quit",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu

        // Update status if we have it
        if MediaKeyTap.isAccessibilityEnabled() {
            updateStatus("Status: Active ✓")
        }
    }

    @objc private func toggleDebugLogging() {
        config.setDebugLoggingEnabled(!config.isDebugLoggingEnabled())
        rebuildMenu()
    }

    func setupMediaKeyTap() {
        mediaKeyTap = MediaKeyTap()
        mediaKeyTap.delegate = self

        if !MediaKeyTap.isAccessibilityEnabled() {
            _ = MediaKeyTap.checkAccessibilityPermission()
            updateStatus("Status: Need Accessibility Permission")
        }

        if mediaKeyTap.start() {
            cgEventTapActive = true
            updateStatus("Status: Active ✓")
        } else {
            cgEventTapActive = false
            updateStatus("Status: Need Accessibility Permission")
        }
    }

    func updateStatus(_ text: String) {
        if let menu = statusItem?.menu,
           let item = menu.item(withTag: 100) {
            item.title = text
        }
    }

    @objc func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func copyDebugInfo(_ sender: NSMenuItem) {
        let bundle  = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build   = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let os      = ProcessInfo.processInfo.operatingSystemVersionString
        let a11y       = MediaKeyTap.isAccessibilityEnabled()
        let logging    = config.isDebugLoggingEnabled()

        var lines: [String] = [
            "## headset_key_to_claude_for_mac — Debug Info",
            "",
            "**Version:** \(version) (build \(build))",
            "**macOS:** \(os)",
            "**Accessibility:** \(a11y ? "granted" : "not granted")",
            "**Event tap active:** \(cgEventTapActive ? "yes" : "no")\(mediaKeyTap?.activeTapLocation.map { " (\($0) level)" } ?? "")",
            "**Mic mode:** \(config.useHeadsetMic() ? "headset" : "default(Mac-side)")",
            "**Debug logging:** \(logging ? "enabled" : "disabled")",
        ]

        let logPath = "/tmp/macmediakeys.log"
        if let log = try? String(contentsOfFile: logPath, encoding: .utf8), !log.isEmpty {
            let logLines = log.components(separatedBy: "\n")
            let trimmed  = logLines.suffix(200).joined(separator: "\n")
            lines += ["", "<details><summary>Log</summary>", "", "```", trimmed, "```", "", "</details>"]
        } else {
            lines += ["", "*(No log — enable Debug Logging in Settings, reproduce the issue, then copy again.)*"]
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)

        sender.title = "Copied!"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            sender.title = "Copy Debug Info"
        }
    }

    @objc func quit() {
        NSApplication.shared.terminate(nil)
    }

    @objc func openAbout() {
        AboutWindowController.show()
    }

    // MARK: - MediaKeyTapDelegate

    func mediaKeyTap(_ tap: MediaKeyTap, receivedKey key: MediaKey) {
        // 改造版: キーボードのメディアキーは転送しない(tap側で素通し済み)。
        // ここでは「物理キー押下の直近証跡」だけを更新する(NowPlaying側ゲートの判定材料)。
        lastTapEventTime = Date()
    }

    // MARK: - NowPlayingInterceptorDelegate

    // ヘッドセットボタンの連打・play/pause二重着弾を1回に潰すデバウンス
    private var lastVoiceTriggerTime: Date = .distantPast
    private static let voiceTriggerDebounce: TimeInterval = 0.3

    // 起動直後はrcdが自動コマンドを送ってくる(起動1秒後のpauseを実測)。
    // 利用者の押下と区別できないため、起動からの猶予中はトリガーを発火しない。
    private let appLaunchTime = Date()
    private static let launchSuppressWindow: TimeInterval = 5.0

    func nowPlayingInterceptor(_ interceptor: NowPlayingInterceptor, receivedKey key: MediaKey, sourceCommand: String) {
        // 直近にCGEventTapの物理キーイベントが無いコマンドは、キーボード由来ではない
        // = Bluetoothヘッドセットのボタン(実測: play/pauseが交互に届く)か、
        //   オーディオルート変化等のシステム発コマンドである。
        if cgEventTapActive,
           Date().timeIntervalSince(lastTapEventTime) > Self.remoteCommandGraceWindow {
            // ヘッドセットボタン → Claude Desktopが最前面の時だけ音声入力トグルを発火。
            // 非最前面時はクレームOFF中のため原則ここへ届かず、届いても何もしない。
            if key == .play, claudeVoiceTrigger.isClaudeFrontmost() {
                let now = Date()
                if now.timeIntervalSince(appLaunchTime) < Self.launchSuppressWindow {
                    debugLog("Voice trigger suppressed — app just launched (rcd auto command) source=\(sourceCommand)")
                    return
                }
                if now.timeIntervalSince(lastVoiceTriggerTime) < Self.voiceTriggerDebounce {
                    debugLog("Voice trigger DEBOUNCED (source=\(sourceCommand))")
                    return
                }
                lastVoiceTriggerTime = now
                debugLog("Voice trigger: headset button source=\(sourceCommand) → fire()")
                claudeVoiceTrigger.fire()
                return
            }
            debugLog("Ignoring remote command \(key) source=\(sourceCommand) — no recent media-key event (headset button or audio route change)")
            return
        }
        // キーボード由来のNowPlayingコマンドも転送しない(改造版はメディア転送を行わない)
        debugLog("NowPlaying command \(key) source=\(sourceCommand) after keyboard event — not forwarded (media forwarding disabled)")
    }
}
