import Cocoa

// 本改造版のリポジトリ。上流(mac-media-keys)へのクレジットはAbout内のCreditsに残している。
private let githubRepoURL = URL(string: "https://github.com/omatoro/headset_key_to_claude_for_mac")!

class AboutWindowController: NSWindowController {
    static var shared: AboutWindowController?

    static func show() {
        if shared == nil {
            shared = AboutWindowController()
        }
        shared?.showWindow(nil)
        shared?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 340),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "About headset_key_to_claude_for_mac"
        window.center()
        window.isReleasedWhenClosed = false

        self.init(window: window)

        let contentView = AboutView(frame: window.contentView!.bounds)
        contentView.autoresizingMask = [.width, .height]
        window.contentView = contentView
    }
}

class AboutView: NSView {
    // 改造版: 更新チェック・上流版インストールのUIは持たない。
    // 上流リリースをインストールすると本改造が上書きされるため。

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        let mainStack = NSStackView()
        mainStack.orientation = .vertical
        mainStack.alignment = .centerX
        mainStack.spacing = 8
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: topAnchor, constant: 28),
            mainStack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            mainStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),
            mainStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            mainStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -24)
        ])

        // App icon
        let iconView = NSImageView()
        iconView.image = NSApp.applicationIconImage
        iconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 80),
            iconView.heightAnchor.constraint(equalToConstant: 80)
        ])
        mainStack.addArrangedSubview(iconView)
        mainStack.setCustomSpacing(14, after: iconView)

        // App name
        let bundle = Bundle.main
        let appName = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? "headset_key_to_claude_for_mac"
        let nameLabel = NSTextField(labelWithString: appName)
        nameLabel.font = NSFont.systemFont(ofSize: 16, weight: .semibold)
        nameLabel.alignment = .center
        mainStack.addArrangedSubview(nameLabel)
        mainStack.setCustomSpacing(3, after: nameLabel)

        // Version
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let versionLabel = NSTextField(labelWithString: "Version \(version) (\(build))")
        versionLabel.font = NSFont.systemFont(ofSize: 11)
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.alignment = .center
        mainStack.addArrangedSubview(versionLabel)
        mainStack.setCustomSpacing(18, after: versionLabel)

        // Separator
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        mainStack.addArrangedSubview(separator)
        NSLayoutConstraint.activate([
            separator.widthAnchor.constraint(equalTo: mainStack.widthAnchor)
        ])
        mainStack.setCustomSpacing(18, after: separator)

        // Credits — the two human credits align into a "label: name" table (like a
        // Finder Get Info panel) rather than each line centering independently, which
        // reads as noticeably more deliberate than three ragged, differently-indented rows.
        // Only the @username is a link — the name itself is plain text.
        // 改造版のクレジット: 上流(mac-media-keys)への謝辞を「Based on」の文脈で明示する。
        let creditsGrid = NSGridView(views: [
            [creditPrefixLabel("Based on mac-media-keys by"), creditNameCell("Ray Hatfield", username: "@rayhatfield", profileURL: URL(string: "https://github.com/rayhatfield")!)],
            [creditPrefixLabel("With contributions from"), creditNameCell("Leopold Stenger", username: "@polderleo", profileURL: URL(string: "https://github.com/polderleo")!)],
            [creditPrefixLabel("Modified by"), creditNameCell("omatoro", username: "@omatoro", profileURL: URL(string: "https://github.com/omatoro")!)]
        ])
        creditsGrid.rowSpacing = 3
        creditsGrid.columnSpacing = 5
        creditsGrid.column(at: 0).xPlacement = .trailing
        creditsGrid.column(at: 1).xPlacement = .leading
        mainStack.addArrangedSubview(creditsGrid)
        mainStack.setCustomSpacing(18, after: creditsGrid)

        // GitHub link
        let githubButton = NSButton(title: "View on GitHub", target: self, action: #selector(viewOnGitHubClicked))
        githubButton.image = NSImage(systemSymbolName: "arrow.up.right", accessibilityDescription: nil)
        githubButton.imagePosition = .imageTrailing
        githubButton.imageScaling = .scaleProportionallyDown
        githubButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
        githubButton.isBordered = false
        githubButton.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        githubButton.contentTintColor = .linkColor
        mainStack.addArrangedSubview(githubButton)
    }

    private func creditPrefixLabel(_ text: String, color: NSColor = .secondaryLabelColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = color
        return label
    }

    /// A "Name (@username)" cell where only the @username is a clickable link to `profileURL`.
    private func creditNameCell(_ name: String, username: String, profileURL: URL) -> NSStackView {
        let nameLabel = NSTextField(labelWithString: "\(name) (")
        nameLabel.font = NSFont.systemFont(ofSize: 11)
        nameLabel.textColor = .labelColor

        let closingLabel = NSTextField(labelWithString: ")")
        closingLabel.font = NSFont.systemFont(ofSize: 11)
        closingLabel.textColor = .labelColor

        let linkButton = creditLinkButton(username, url: profileURL)

        let row = NSStackView(views: [nameLabel, linkButton, closingLabel])
        row.orientation = .horizontal
        row.spacing = 0
        // NSButton reserves title padding even when borderless; pull the
        // parentheses in so it reads as a tight "(@username)" rather than
        // "( @username )".
        row.setCustomSpacing(-2, after: nameLabel)
        row.setCustomSpacing(-2, after: linkButton)
        return row
    }

    /// A borderless, link-colored button used for a clickable credit name.
    private func creditLinkButton(_ title: String, url: URL, fontSize: CGFloat = 11) -> NSButton {
        let button = NSButton(title: title, target: self, action: #selector(creditLinkClicked(_:)))
        button.isBordered = false
        button.font = NSFont.systemFont(ofSize: fontSize)
        button.contentTintColor = .linkColor
        button.identifier = NSUserInterfaceItemIdentifier(url.absoluteString)
        return button
    }

    @objc private func creditLinkClicked(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let url = URL(string: raw) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func viewOnGitHubClicked() {
        NSWorkspace.shared.open(githubRepoURL)
    }
}
