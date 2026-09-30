import AppKit

final class SettingsWindowController: NSWindowController {
    private let heading = NSTextField(labelWithString: "")
    private let languageLabel = NSTextField(labelWithString: "")
    private let outputLabel = NSTextField(labelWithString: "")
    private let themeLabel = NSTextField(labelWithString: "")
    private let themeValue = NSTextField(labelWithString: "")
    private let qualityLabel = NSTextField(labelWithString: "")
    private let updatesHeading = NSTextField(labelWithString: "")
    private let languagePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let outputPath = NSTextField(labelWithString: "")
    private let chooseButton = NSButton(title: "", target: nil, action: nil)
    private let qualityPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let minimizeCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let autoUpdateCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let checkButton = NSButton(title: "", target: nil, action: nil)

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 470),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.center()
        super.init(window: window)
        buildUI()
        reloadTexts()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildUI() {
        guard let content = window?.contentView else { return }
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 28, bottom: 24, right: 28)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor)
        ])

        heading.font = .systemFont(ofSize: 20, weight: .bold)
        stack.addArrangedSubview(heading)
        stack.addArrangedSubview(row(label: languageLabel, control: languagePopup))
        languagePopup.target = self
        languagePopup.action = #selector(languageChanged)

        let outputRow = NSStackView()
        outputRow.orientation = .horizontal
        outputRow.alignment = .centerY
        outputPath.lineBreakMode = .byTruncatingMiddle
        outputPath.textColor = .secondaryLabelColor
        outputRow.addArrangedSubview(outputPath)
        chooseButton.target = self
        chooseButton.action = #selector(chooseOutput)
        outputRow.addArrangedSubview(chooseButton)
        stack.addArrangedSubview(row(label: outputLabel, control: outputRow))

        themeValue.textColor = .secondaryLabelColor
        stack.addArrangedSubview(row(label: themeLabel, control: themeValue))
        qualityPopup.target = self
        qualityPopup.action = #selector(qualityChanged)
        stack.addArrangedSubview(row(label: qualityLabel, control: qualityPopup))

        minimizeCheckbox.target = self
        minimizeCheckbox.action = #selector(minimizeChanged)
        stack.addArrangedSubview(minimizeCheckbox)
        stack.setCustomSpacing(24, after: minimizeCheckbox)

        updatesHeading.font = .systemFont(ofSize: 14, weight: .semibold)
        stack.addArrangedSubview(updatesHeading)
        autoUpdateCheckbox.target = self
        autoUpdateCheckbox.action = #selector(autoUpdateChanged)
        stack.addArrangedSubview(autoUpdateCheckbox)
        checkButton.target = NSApp.delegate
        checkButton.action = #selector(AppDelegate.checkForUpdates)
        stack.addArrangedSubview(checkButton)
    }

    private func row(label: NSTextField, control: NSView) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.widthAnchor.constraint(equalToConstant: 155).isActive = true
        row.addArrangedSubview(label)
        control.widthAnchor.constraint(greaterThanOrEqualToConstant: 300).isActive = true
        row.addArrangedSubview(control)
        return row
    }

    func reloadTexts() {
        window?.title = tr("settings.title")
        heading.stringValue = tr("settings.general")
        languageLabel.stringValue = tr("settings.language")
        outputLabel.stringValue = tr("settings.output")
        chooseButton.title = tr("settings.choose")
        themeLabel.stringValue = tr("settings.theme")
        themeValue.stringValue = tr("settings.theme.system")
        qualityLabel.stringValue = tr("settings.quality")
        minimizeCheckbox.title = tr("settings.minimize")
        updatesHeading.stringValue = tr("settings.updates")
        autoUpdateCheckbox.title = tr("settings.autoUpdates")
        checkButton.title = tr("settings.check")

        languagePopup.removeAllItems()
        languagePopup.addItems(withTitles: [tr("settings.language.auto"), tr("settings.language.en"), tr("settings.language.ru")])
        let languages: [AppLanguage] = [.automatic, .english, .russian]
        languagePopup.selectItem(at: languages.firstIndex(of: Preferences.language) ?? 0)

        qualityPopup.removeAllItems()
        qualityPopup.addItems(withTitles: [tr("settings.quality.economy"), tr("settings.quality.balanced"), tr("settings.quality.smooth")])
        qualityPopup.selectItem(at: min(max(Preferences.qualityIndex, 0), 2))
        outputPath.stringValue = Preferences.outputDirectory.path
        minimizeCheckbox.state = Preferences.minimizeOnRecord ? .on : .off
        autoUpdateCheckbox.state = Preferences.autoUpdates ? .on : .off
    }

    @objc private func languageChanged() {
        let values: [AppLanguage] = [.automatic, .english, .russian]
        L10n.shared.setLanguage(values[min(max(languagePopup.indexOfSelectedItem, 0), values.count - 1)])
    }

    @objc private func chooseOutput() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = Preferences.outputDirectory
        panel.beginSheetModal(for: window!) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Preferences.outputDirectory = url
            self?.outputPath.stringValue = url.path
        }
    }

    @objc private func qualityChanged() { Preferences.qualityIndex = qualityPopup.indexOfSelectedItem }
    @objc private func minimizeChanged() { Preferences.minimizeOnRecord = minimizeCheckbox.state == .on }

    @objc private func autoUpdateChanged() {
        (NSApp.delegate as? AppDelegate)?.setAutomaticUpdates(autoUpdateCheckbox.state == .on)
    }
}
