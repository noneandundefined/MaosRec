import AppKit
import AVFoundation
import CoreGraphics

final class MainWindowController: NSWindowController, ScreenRecorderDelegate {
    private enum Page: Int {
        case record, camera, audio, settings, help, about
    }

    private enum CaptureMode {
        case screen, window, area
    }

    private struct WindowChoice {
        let title: String
        let bounds: CGRect
    }

    private let recorder = ScreenRecorder()
    private var videoDevices: [AVCaptureDevice] = []
    private var audioDevices: [AVCaptureDevice] = []
    private var displays: [(id: CGDirectDisplayID, name: String)] = []
    private var windows: [WindowChoice] = []
    private var page: Page = .record
    private var mode: CaptureMode = .screen
    private var timer: Timer?
    private var startedAt: Date?
    private var lastSavedURL: URL?
    private var terminatingAfterSave = false

    private var navButtons: [Page: NSButton] = [:]
    private let sourceHeading = NSTextField(labelWithString: "")
    private let panelHeading = NSTextField(labelWithString: "")
    private let recordCaption = NSTextField(labelWithString: "")
    private let shortcutBadge = NSTextField(labelWithString: "⌘R")
    private let statusLabel = NSTextField(labelWithString: "")
    private let modeHint = NSTextField(labelWithString: "")
    private let screenRow = MenuRow(icon: Glyph.image(.display))
    private let cameraRow = MenuRow(icon: Glyph.image(.camera))
    private let audioRow = MenuRow(icon: Glyph.image(.mic))
    private let formatRow = MenuRow(icon: Glyph.image(.gear))
    private let qualityRow = MenuRow(icon: Glyph.image(.sliders))
    private let screenModeButton = NSButton(title: "", target: nil, action: nil)
    private let windowModeButton = NSButton(title: "", target: nil, action: nil)
    private let areaModeButton = NSButton(title: "", target: nil, action: nil)
    private let recordButton = NSButton(title: "", target: nil, action: nil)
    private let showFileButton = NSButton(title: "", target: nil, action: nil)
    private let preview = PreviewCanvas()

    private let recordChrome = NSView()
    private let extraStack = NSStackView()
    private let cameraPage = NSStackView()
    private let audioPage = NSStackView()
    private let settingsPage = NSStackView()
    private let helpPage = NSStackView()
    private let aboutPage = NSStackView()

    private let cameraPageText = NSTextField(wrappingLabelWithString: "")
    private let positionLabel = NSTextField(labelWithString: "")
    private let sizeLabel = NSTextField(labelWithString: "")
    private let positionPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let cameraSizeSlider = NSSlider(value: Preferences.cameraScale, minValue: 0.15, maxValue: 0.38, target: nil, action: nil)
    private let audioPageText = NSTextField(wrappingLabelWithString: "")
    private let helpText = NSTextField(wrappingLabelWithString: "")
    private let aboutVersion = NSTextField(labelWithString: "")
    private let aboutSystem = NSTextField(labelWithString: "")

    private let settingsHeading = NSTextField(labelWithString: "")
    private let languageLabel = NSTextField(labelWithString: "")
    private let outputLabel = NSTextField(labelWithString: "")
    private let themeLabel = NSTextField(labelWithString: "")
    private let themeValue = NSTextField(labelWithString: "")
    private let settingsQualityLabel = NSTextField(labelWithString: "")
    private let updatesHeading = NSTextField(labelWithString: "")
    private let languagePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let outputPath = NSTextField(labelWithString: "")
    private let chooseButton = NSButton(title: "", target: nil, action: nil)
    private let settingsQualityPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let minimizeCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let autoUpdateCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let checkButton = NSButton(title: "", target: nil, action: nil)

    private var displayPopup: NSPopUpButton { screenRow.popup }
    private var cameraPopup: NSPopUpButton { cameraRow.popup }
    private var audioPopup: NSPopUpButton { audioRow.popup }
    private var qualityPopup: NSPopUpButton { qualityRow.popup }

    var isRecording: Bool { recorder.isRecording }
    var isBusy: Bool { recorder.isBusy }

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1120, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Maos Record"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isOpaque = true
        window.backgroundColor = Chrome.window
        window.minSize = NSSize(width: 960, height: 620)
        window.center()
        super.init(window: window)
        recorder.delegate = self
        buildUI()
        reloadDevices()
        reloadTexts()
        show(page: .record)
        (window.contentView as? FillView)?.onAppearanceChange = { [weak self] in
            self?.reloadTexts()
        }
        NotificationCenter.default.addObserver(self, selector: #selector(reloadTexts), name: .languageDidChange, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func showSettingsPage() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        show(page: .settings)
    }

    private func buildUI() {
        let content = FillView(fill: Chrome.window)
        content.wantsLayer = true
        window?.contentView = content
        paint(content, Chrome.window)

        let sidebar = FillView(fill: Chrome.sidebar)
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(sidebar)

        let sideStack = NSStackView()
        sideStack.orientation = .vertical
        sideStack.alignment = .leading
        sideStack.spacing = 4
        sideStack.edgeInsets = NSEdgeInsets(top: 18, left: 14, bottom: 16, right: 14)
        sideStack.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(sideStack)

        sideStack.addArrangedSubview(brandHeader())
        sideStack.setCustomSpacing(22, after: sideStack.arrangedSubviews.last!)
        sideStack.addArrangedSubview(navButton(.record, icon: .display))
        sideStack.addArrangedSubview(navButton(.camera, icon: .camera))
        sideStack.addArrangedSubview(navButton(.audio, icon: .mic))
        sideStack.addArrangedSubview(navButton(.settings, icon: .gear))

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        sideStack.addArrangedSubview(spacer)

        let helpButton = navButton(.help, icon: .help)
        let aboutButton = navButton(.about, icon: .about)
        let languageButton = navButton(.record, icon: .language)
        languageButton.tag = -1
        languageButton.action = #selector(languageMenuPressed(_:))
        languageButton.identifier = NSUserInterfaceItemIdentifier("language")
        sideStack.addArrangedSubview(helpButton)
        sideStack.addArrangedSubview(languageButton)
        sideStack.addArrangedSubview(aboutButton)
        navButtons[.help] = helpButton
        navButtons[.about] = aboutButton

        recordChrome.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(recordChrome)
        buildRecordChrome()

        extraStack.orientation = .vertical
        extraStack.alignment = .leading
        extraStack.spacing = 14
        extraStack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(extraStack)
        buildExtraPages()

        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: content.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 232),

            sideStack.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor),
            sideStack.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            sideStack.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 36),
            sideStack.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor),

            recordChrome.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            recordChrome.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            recordChrome.topAnchor.constraint(equalTo: content.topAnchor),
            recordChrome.bottomAnchor.constraint(equalTo: content.bottomAnchor),

            extraStack.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: 32),
            extraStack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -32),
            extraStack.topAnchor.constraint(equalTo: content.topAnchor, constant: 48),
            extraStack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -24)
        ])
    }

    private func brandHeader() -> NSView {
        let icon = NSImageView()
        icon.image = NSApp.applicationIconImage ?? AppIcon.make()
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 42).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 42).isActive = true

        let name = NSTextField(labelWithString: "Maos Record")
        name.font = .systemFont(ofSize: 16, weight: .bold)
        name.textColor = Chrome.text
        let tagline = NSTextField(labelWithString: tr("brand.tagline"))
        tagline.font = .systemFont(ofSize: 11)
        tagline.textColor = Chrome.secondary
        tagline.identifier = NSUserInterfaceItemIdentifier("tagline")

        let text = NSStackView(views: [name, tagline])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 1

        let row = NSStackView(views: [icon, text])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.edgeInsets = NSEdgeInsets(top: 0, left: 6, bottom: 8, right: 0)
        return row
    }

    private func navButton(_ page: Page, icon: Glyph.Kind) -> NSButton {
        let button = NSButton(title: "", target: self, action: #selector(navPressed(_:)))
        button.tag = page.rawValue
        button.isBordered = false
        button.image = Glyph.image(icon)
        button.imagePosition = .imageLeading
        button.alignment = .left
        button.font = .systemFont(ofSize: 13, weight: .medium)
        button.wantsLayer = true
        button.layer?.cornerRadius = 8
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 204).isActive = true
        button.heightAnchor.constraint(equalToConstant: 34).isActive = true
        if page != .record || navButtons[.record] == nil, page != .help, page != .about {
            navButtons[page] = button
        }
        if page == .record, navButtons[.record] == nil {
            navButtons[.record] = button
        }
        return button
    }

    private func buildRecordChrome() {
        let center = NSView()
        center.translatesAutoresizingMaskIntoConstraints = false
        let right = FillView(fill: Chrome.window)
        right.translatesAutoresizingMaskIntoConstraints = false
        recordChrome.addSubview(center)
        recordChrome.addSubview(right)

        sourceHeading.font = .systemFont(ofSize: 15, weight: .semibold)
        sourceHeading.textColor = Chrome.text
        preview.translatesAutoresizingMaskIntoConstraints = false

        screenModeButton.target = self
        screenModeButton.action = #selector(modePressed(_:))
        screenModeButton.tag = 0
        windowModeButton.target = self
        windowModeButton.action = #selector(modePressed(_:))
        windowModeButton.tag = 1
        areaModeButton.target = self
        areaModeButton.action = #selector(modePressed(_:))
        areaModeButton.tag = 2
        for button in [screenModeButton, windowModeButton, areaModeButton] {
            button.isBordered = false
            button.imagePosition = .imageLeading
            button.wantsLayer = true
            button.layer?.cornerRadius = 10
            button.heightAnchor.constraint(equalToConstant: 40).isActive = true
        }
        screenModeButton.image = Glyph.image(.display)
        windowModeButton.image = Glyph.image(.window)
        areaModeButton.image = Glyph.image(.area)

        let modes = NSStackView(views: [screenModeButton, windowModeButton, areaModeButton])
        modes.orientation = .horizontal
        modes.distribution = .fillEqually
        modes.spacing = 10
        modes.translatesAutoresizingMaskIntoConstraints = false

        modeHint.font = .systemFont(ofSize: 12)
        modeHint.textColor = Chrome.secondary
        modeHint.maximumNumberOfLines = 2

        center.addSubview(sourceHeading)
        center.addSubview(preview)
        center.addSubview(modes)
        center.addSubview(modeHint)
        sourceHeading.translatesAutoresizingMaskIntoConstraints = false
        modeHint.translatesAutoresizingMaskIntoConstraints = false

        panelHeading.font = .systemFont(ofSize: 15, weight: .semibold)
        panelHeading.textColor = Chrome.text
        recordButton.image = RecordArt.start
        recordButton.imagePosition = .imageOnly
        recordButton.isBordered = false
        recordButton.target = self
        recordButton.action = #selector(recordPressed)
        recordButton.keyEquivalent = "r"
        recordButton.keyEquivalentModifierMask = .command
        recordButton.translatesAutoresizingMaskIntoConstraints = false
        recordCaption.font = .systemFont(ofSize: 13, weight: .semibold)
        recordCaption.textColor = Chrome.text
        shortcutBadge.font = .systemFont(ofSize: 11, weight: .medium)
        shortcutBadge.textColor = Chrome.secondary
        shortcutBadge.drawsBackground = true
        shortcutBadge.backgroundColor = Chrome.card
        shortcutBadge.isBezeled = false
        shortcutBadge.alignment = .center
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = Chrome.secondary
        statusLabel.alignment = .center
        showFileButton.isBordered = false
        showFileButton.target = self
        showFileButton.action = #selector(showLastFile)
        showFileButton.isHidden = true

        let captionRow = NSStackView(views: [recordCaption, shortcutBadge])
        captionRow.orientation = .horizontal
        captionRow.alignment = .centerY
        captionRow.spacing = 8

        screenRow.popup.target = self
        cameraRow.popup.target = self
        cameraRow.popup.action = #selector(cameraPicked)
        audioRow.popup.target = self
        audioRow.popup.action = #selector(audioPicked)
        qualityRow.popup.target = self
        qualityRow.popup.action = #selector(qualityPicked)
        formatRow.popup.addItem(withTitle: tr("format.mp4"))

        let rightStack = NSStackView()
        rightStack.orientation = .vertical
        rightStack.alignment = .centerX
        rightStack.spacing = 10
        rightStack.edgeInsets = NSEdgeInsets(top: 28, left: 18, bottom: 20, right: 18)
        rightStack.translatesAutoresizingMaskIntoConstraints = false
        right.addSubview(rightStack)
        panelHeading.translatesAutoresizingMaskIntoConstraints = false
        rightStack.addArrangedSubview(panelHeading)
        rightStack.setCustomSpacing(18, after: panelHeading)
        rightStack.addArrangedSubview(recordButton)
        rightStack.addArrangedSubview(captionRow)
        rightStack.addArrangedSubview(statusLabel)
        rightStack.addArrangedSubview(showFileButton)
        rightStack.setCustomSpacing(18, after: showFileButton)
        for row in [screenRow, cameraRow, audioRow, formatRow, qualityRow] {
            rightStack.addArrangedSubview(row)
            row.translatesAutoresizingMaskIntoConstraints = false
            row.widthAnchor.constraint(equalTo: rightStack.widthAnchor, constant: -36).isActive = true
        }
        panelHeading.widthAnchor.constraint(equalTo: rightStack.widthAnchor, constant: -36).isActive = true
        statusLabel.widthAnchor.constraint(equalTo: rightStack.widthAnchor, constant: -36).isActive = true

        NSLayoutConstraint.activate([
            center.leadingAnchor.constraint(equalTo: recordChrome.leadingAnchor),
            center.topAnchor.constraint(equalTo: recordChrome.topAnchor),
            center.bottomAnchor.constraint(equalTo: recordChrome.bottomAnchor),
            center.trailingAnchor.constraint(equalTo: right.leadingAnchor),

            right.trailingAnchor.constraint(equalTo: recordChrome.trailingAnchor),
            right.topAnchor.constraint(equalTo: recordChrome.topAnchor),
            right.bottomAnchor.constraint(equalTo: recordChrome.bottomAnchor),
            right.widthAnchor.constraint(equalToConstant: 292),

            rightStack.leadingAnchor.constraint(equalTo: right.leadingAnchor),
            rightStack.trailingAnchor.constraint(equalTo: right.trailingAnchor),
            rightStack.topAnchor.constraint(equalTo: right.topAnchor, constant: 20),

            sourceHeading.leadingAnchor.constraint(equalTo: center.leadingAnchor, constant: 28),
            sourceHeading.topAnchor.constraint(equalTo: center.topAnchor, constant: 28),

            preview.leadingAnchor.constraint(equalTo: center.leadingAnchor, constant: 28),
            preview.trailingAnchor.constraint(equalTo: center.trailingAnchor, constant: -20),
            preview.topAnchor.constraint(equalTo: sourceHeading.bottomAnchor, constant: 16),

            modes.leadingAnchor.constraint(equalTo: preview.leadingAnchor),
            modes.trailingAnchor.constraint(equalTo: preview.trailingAnchor),
            modes.topAnchor.constraint(equalTo: preview.bottomAnchor, constant: 16),

            modeHint.leadingAnchor.constraint(equalTo: preview.leadingAnchor),
            modeHint.trailingAnchor.constraint(equalTo: preview.trailingAnchor),
            modeHint.topAnchor.constraint(equalTo: modes.bottomAnchor, constant: 8),
            modeHint.bottomAnchor.constraint(equalTo: center.bottomAnchor, constant: -20),

            recordButton.widthAnchor.constraint(equalToConstant: 96),
            recordButton.heightAnchor.constraint(equalToConstant: 96)
        ])
    }

    private func buildExtraPages() {
        configurePage(cameraPage)
        configurePage(audioPage)
        configurePage(settingsPage)
        configurePage(helpPage)
        configurePage(aboutPage)
        for page in [cameraPage, audioPage, settingsPage, helpPage, aboutPage] {
            extraStack.addArrangedSubview(page)
            page.translatesAutoresizingMaskIntoConstraints = false
            page.widthAnchor.constraint(equalTo: extraStack.widthAnchor).isActive = true
        }

        cameraPageText.maximumNumberOfLines = 0
        cameraPageText.textColor = Chrome.secondary
        cameraPageText.preferredMaxLayoutWidth = 520
        positionLabel.textColor = Chrome.secondary
        sizeLabel.textColor = Chrome.secondary
        positionPopup.target = self
        positionPopup.action = #selector(cameraLayoutChanged)
        cameraSizeSlider.target = self
        cameraSizeSlider.action = #selector(cameraLayoutChanged)
        cameraPage.addArrangedSubview(cameraPageText)
        cameraPage.addArrangedSubview(labeled(positionLabel, positionPopup))
        cameraPage.addArrangedSubview(labeled(sizeLabel, cameraSizeSlider))

        audioPageText.maximumNumberOfLines = 0
        audioPageText.textColor = Chrome.secondary
        audioPageText.preferredMaxLayoutWidth = 520
        audioPage.addArrangedSubview(audioPageText)

        helpText.maximumNumberOfLines = 0
        helpText.textColor = Chrome.text
        helpText.preferredMaxLayoutWidth = 560
        helpPage.addArrangedSubview(helpText)

        let aboutIcon = NSImageView()
        aboutIcon.image = NSApp.applicationIconImage ?? AppIcon.make()
        aboutIcon.imageScaling = .scaleProportionallyUpOrDown
        aboutIcon.translatesAutoresizingMaskIntoConstraints = false
        aboutIcon.widthAnchor.constraint(equalToConstant: 72).isActive = true
        aboutIcon.heightAnchor.constraint(equalToConstant: 72).isActive = true
        let aboutName = NSTextField(labelWithString: "Maos Record")
        aboutName.font = .systemFont(ofSize: 22, weight: .bold)
        aboutName.textColor = Chrome.text
        aboutVersion.textColor = Chrome.secondary
        aboutSystem.textColor = Chrome.secondary
        aboutPage.addArrangedSubview(aboutIcon)
        aboutPage.addArrangedSubview(aboutName)
        aboutPage.addArrangedSubview(aboutVersion)
        aboutPage.addArrangedSubview(aboutSystem)

        settingsHeading.font = .systemFont(ofSize: 20, weight: .bold)
        settingsHeading.textColor = Chrome.text
        updatesHeading.font = .systemFont(ofSize: 14, weight: .semibold)
        updatesHeading.textColor = Chrome.text
        languagePopup.target = self
        languagePopup.action = #selector(languageChanged)
        chooseButton.target = self
        chooseButton.action = #selector(chooseOutput)
        settingsQualityPopup.target = self
        settingsQualityPopup.action = #selector(settingsQualityChanged)
        minimizeCheckbox.target = self
        minimizeCheckbox.action = #selector(minimizeChanged)
        autoUpdateCheckbox.target = self
        autoUpdateCheckbox.action = #selector(autoUpdateChanged)
        checkButton.target = NSApp.delegate
        checkButton.action = #selector(AppDelegate.checkForUpdates)
        outputPath.lineBreakMode = .byTruncatingMiddle
        outputPath.textColor = Chrome.secondary
        themeValue.textColor = Chrome.secondary
        let outputRow = NSStackView(views: [outputPath, chooseButton])
        outputRow.orientation = .horizontal
        settingsPage.addArrangedSubview(settingsHeading)
        settingsPage.addArrangedSubview(labeled(languageLabel, languagePopup))
        settingsPage.addArrangedSubview(labeled(outputLabel, outputRow))
        settingsPage.addArrangedSubview(labeled(themeLabel, themeValue))
        settingsPage.addArrangedSubview(labeled(settingsQualityLabel, settingsQualityPopup))
        settingsPage.addArrangedSubview(minimizeCheckbox)
        settingsPage.addArrangedSubview(updatesHeading)
        settingsPage.addArrangedSubview(autoUpdateCheckbox)
        settingsPage.addArrangedSubview(checkButton)
    }

    private func configurePage(_ stack: NSStackView) {
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
    }

    private func labeled(_ label: NSTextField, _ control: NSView) -> NSView {
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = Chrome.text
        control.translatesAutoresizingMaskIntoConstraints = false
        control.widthAnchor.constraint(greaterThanOrEqualToConstant: 280).isActive = true
        let row = NSStackView(views: [label, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 16
        label.widthAnchor.constraint(equalToConstant: 180).isActive = true
        return row
    }

    @objc private func reloadTexts() {
        screenRow.refreshChrome()
        cameraRow.refreshChrome()
        audioRow.refreshChrome()
        formatRow.refreshChrome()
        qualityRow.refreshChrome()
        if let content = window?.contentView { paint(content, Chrome.window) }
        shortcutBadge.textColor = Chrome.secondary
        shortcutBadge.backgroundColor = Chrome.card
        (findTagline())?.stringValue = tr("brand.tagline")
        setNav(.record, tr("nav.record"))
        setNav(.camera, tr("nav.camera"))
        setNav(.audio, tr("nav.audio"))
        setNav(.settings, tr("nav.settings"))
        setNav(.help, tr("nav.help"))
        setNav(.about, tr("nav.about"))
        if let languageButton = languageButton() {
            setButtonTitle(languageButton, tr("nav.language"), color: Chrome.secondary, alignment: .left)
            languageButton.contentTintColor = Chrome.secondary
        }
        sourceHeading.stringValue = tr("source.heading")
        panelHeading.stringValue = tr("panel.record")
        screenRow.titleLabel.stringValue = mode == .window ? tr("field.window") : tr("field.screen")
        cameraRow.titleLabel.stringValue = tr("field.camera")
        audioRow.titleLabel.stringValue = tr("field.microphone")
        formatRow.titleLabel.stringValue = tr("field.format")
        qualityRow.titleLabel.stringValue = tr("field.quality")
        setButtonTitle(screenModeButton, tr("mode.screen"), color: mode == .screen ? .white : Chrome.secondary, alignment: .center)
        setButtonTitle(windowModeButton, tr("mode.window"), color: mode == .window ? .white : Chrome.secondary, alignment: .center)
        setButtonTitle(areaModeButton, tr("mode.area"), color: mode == .area ? .white : Chrome.secondary, alignment: .center)
        styleModeButtons()
        cameraPageText.stringValue = tr("camera.page")
        positionLabel.stringValue = tr("camera.position")
        sizeLabel.stringValue = tr("camera.size")
        audioPageText.stringValue = tr("audio.page")
        helpText.stringValue = tr("help.body")
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        aboutVersion.stringValue = String(format: tr("about.version"), version)
        aboutSystem.stringValue = tr("about.system")
        showFileButton.attributedTitle = NSAttributedString(string: tr("menu.showFile"), attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: Chrome.accent
        ])
        updateModeHint()
        reloadSettingsTexts()
        reloadDevices()
        updateStatus()
        styleNav()
    }

    private func reloadSettingsTexts() {
        settingsHeading.stringValue = tr("settings.general")
        languageLabel.stringValue = tr("settings.language")
        outputLabel.stringValue = tr("settings.output")
        chooseButton.title = tr("settings.choose")
        themeLabel.stringValue = tr("settings.theme")
        themeValue.stringValue = tr("settings.theme.system")
        settingsQualityLabel.stringValue = tr("settings.quality")
        minimizeCheckbox.attributedTitle = NSAttributedString(string: tr("settings.minimize"), attributes: [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: Chrome.text
        ])
        updatesHeading.stringValue = tr("settings.updates")
        autoUpdateCheckbox.attributedTitle = NSAttributedString(string: tr("settings.autoUpdates"), attributes: [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: Chrome.text
        ])
        checkButton.title = tr("settings.check")
        languagePopup.removeAllItems()
        languagePopup.addItems(withTitles: [tr("settings.language.auto"), tr("settings.language.en"), tr("settings.language.ru")])
        let languages: [AppLanguage] = [.automatic, .english, .russian]
        languagePopup.selectItem(at: languages.firstIndex(of: Preferences.language) ?? 0)
        settingsQualityPopup.removeAllItems()
        settingsQualityPopup.addItems(withTitles: [tr("settings.quality.economy"), tr("settings.quality.balanced"), tr("settings.quality.smooth")])
        settingsQualityPopup.selectItem(at: min(max(Preferences.qualityIndex, 0), 2))
        outputPath.stringValue = Preferences.outputDirectory.path
        minimizeCheckbox.state = Preferences.minimizeOnRecord ? .on : .off
        autoUpdateCheckbox.state = Preferences.autoUpdates ? .on : .off
    }

    private func reloadDevices() {
        let previousCamera = cameraPopup.titleOfSelectedItem
        let previousAudio = audioPopup.titleOfSelectedItem
        let previousScreen = displayPopup.indexOfSelectedItem
        displays = NSScreen.screens.enumerated().compactMap { index, screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return (number.uint32Value, "\(tr("source.display")) \(index + 1)")
        }
        videoDevices = ScreenRecorder.videoDevices
        audioDevices = ScreenRecorder.audioDevices
        refill(cameraPopup, none: tr("source.none.camera"), names: videoDevices.map(\.localizedName), previous: previousCamera, preferOn: Preferences.recordCamera)
        refill(audioPopup, none: tr("source.none.mic"), names: audioDevices.map(\.localizedName), previous: previousAudio, preferOn: Preferences.recordMicrophone)
        reloadScreenPopup(preferredIndex: previousScreen)
        qualityPopup.removeAllItems()
        qualityPopup.addItems(withTitles: [tr("quality.economy.menu"), tr("quality.balanced.menu"), tr("quality.smooth.menu")])
        qualityPopup.selectItem(at: min(max(Preferences.qualityIndex, 0), 2))
        formatRow.popup.removeAllItems()
        formatRow.popup.addItem(withTitle: tr("format.mp4"))
        positionPopup.removeAllItems()
        positionPopup.addItems(withTitles: [tr("camera.topLeft"), tr("camera.topRight"), tr("camera.bottomLeft"), tr("camera.bottomRight")])
        let positions: [CameraPosition] = [.topLeft, .topRight, .bottomLeft, .bottomRight]
        positionPopup.selectItem(at: positions.firstIndex(of: Preferences.cameraPosition) ?? 3)
        preview.cameraEnabled = cameraPopup.indexOfSelectedItem > 0
        preview.cameraPosition = Preferences.cameraPosition
        preview.cameraScale = CGFloat(Preferences.cameraScale)
        preview.needsDisplay = true
    }

    private func refill(_ popup: NSPopUpButton, none: String, names: [String], previous: String?, preferOn: Bool) {
        popup.removeAllItems()
        popup.addItem(withTitle: none)
        popup.addItems(withTitles: names)
        if let previous = previous, popup.itemTitles.contains(previous), previous != none {
            popup.selectItem(withTitle: previous)
        } else if preferOn, !names.isEmpty {
            popup.selectItem(at: 1)
        } else {
            popup.selectItem(at: 0)
        }
    }

    private func reloadScreenPopup(preferredIndex: Int) {
        displayPopup.removeAllItems()
        if mode == .window {
            windows = loadWindows()
            if windows.isEmpty {
                displayPopup.addItem(withTitle: tr("source.noWindow"))
            } else {
                displayPopup.addItems(withTitles: windows.map(\.title))
                let index = min(max(preferredIndex, 0), windows.count - 1)
                displayPopup.selectItem(at: index)
            }
        } else if displays.count <= 1 {
            displayPopup.addItem(withTitle: tr("source.entire"))
        } else {
            displayPopup.addItems(withTitles: displays.map(\.name))
            displayPopup.selectItem(at: min(max(preferredIndex, 0), displays.count - 1))
        }
        screenRow.titleLabel.stringValue = mode == .window ? tr("field.window") : tr("field.screen")
        screenRow.iconView.image = Glyph.image(mode == .window ? .window : .display)
    }

    private func loadWindows() -> [WindowChoice] {
        guard let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var result: [WindowChoice] = []
        for item in raw {
            let layer = (item[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            guard layer == 0 else { continue }
            let ownerPID = (item[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? -1
            if ownerPID == ownPID { continue }
            guard let dict = item[kCGWindowBounds as String] as? [String: Any],
                  let x = (dict["X"] as? NSNumber)?.doubleValue,
                  let y = (dict["Y"] as? NSNumber)?.doubleValue,
                  let width = (dict["Width"] as? NSNumber)?.doubleValue,
                  let height = (dict["Height"] as? NSNumber)?.doubleValue,
                  width >= 120, height >= 80 else { continue }
            let bounds = CGRect(x: x, y: y, width: width, height: height)
            let owner = item[kCGWindowOwnerName as String] as? String ?? ""
            let name = item[kCGWindowName as String] as? String ?? ""
            let title = name.isEmpty ? owner : "\(owner) — \(name)"
            guard !title.isEmpty else { continue }
            result.append(WindowChoice(title: String(title.prefix(80)), bounds: bounds))
            if result.count == 40 { break }
        }
        return result
    }

    private func show(page: Page) {
        self.page = page
        recordChrome.isHidden = page != .record
        extraStack.isHidden = page == .record
        cameraPage.isHidden = page != .camera
        audioPage.isHidden = page != .audio
        settingsPage.isHidden = page != .settings
        helpPage.isHidden = page != .help
        aboutPage.isHidden = page != .about
        styleNav()
    }

    private func styleNav() {
        for (item, button) in navButtons {
            let chosen = item == page
            paint(button, chosen ? Chrome.selected : Chrome.sidebar)
            setButtonTitle(button, buttonTitle(item), color: chosen ? Chrome.text : Chrome.secondary, alignment: .left, weight: chosen ? .semibold : .medium)
            button.contentTintColor = chosen ? Chrome.text : Chrome.secondary
        }
    }

    private func buttonTitle(_ item: Page) -> String {
        switch item {
        case .record: return tr("nav.record")
        case .camera: return tr("nav.camera")
        case .audio: return tr("nav.audio")
        case .settings: return tr("nav.settings")
        case .help: return tr("nav.help")
        case .about: return tr("nav.about")
        }
    }

    private func setNav(_ item: Page, _ title: String) {
        guard let button = navButtons[item] else { return }
        setButtonTitle(button, title, color: item == page ? Chrome.text : Chrome.secondary, alignment: .left)
    }

    private func styleModeButtons() {
        styleMode(screenModeButton, chosen: mode == .screen)
        styleMode(windowModeButton, chosen: mode == .window)
        styleMode(areaModeButton, chosen: mode == .area)
    }

    private func styleMode(_ button: NSButton, chosen: Bool) {
        paint(button, chosen ? Chrome.accent : Chrome.card)
        button.contentTintColor = chosen ? NSColor.white : Chrome.secondary
    }

    private func updateModeHint() {
        switch mode {
        case .screen:
            modeHint.stringValue = ""
            modeHint.isHidden = true
        case .window:
            modeHint.stringValue = tr("window.hint")
            modeHint.isHidden = false
        case .area:
            modeHint.stringValue = tr("area.hint")
            modeHint.isHidden = false
        }
        preview.style = mode == .area ? .area : (mode == .window ? .window : .screen)
        preview.needsDisplay = true
    }

    @objc private func navPressed(_ sender: NSButton) {
        guard !recorder.isRecording, let next = Page(rawValue: sender.tag) else { return }
        show(page: next)
    }

    @objc private func languageMenuPressed(_ sender: NSButton) {
        let menu = NSMenu()
        let values: [(AppLanguage, String)] = [
            (.automatic, tr("settings.language.auto")),
            (.english, tr("settings.language.en")),
            (.russian, tr("settings.language.ru"))
        ]
        for entry in values {
            let item = NSMenuItem(title: entry.1, action: #selector(languageItemPressed(_:)), keyEquivalent: "")
            item.target = self
            item.state = Preferences.language == entry.0 ? .on : .off
            item.representedObject = entry.0.rawValue
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    @objc private func languageItemPressed(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let language = AppLanguage(rawValue: raw) else { return }
        L10n.shared.setLanguage(language)
    }

    @objc private func modePressed(_ sender: NSButton) {
        guard !recorder.isRecording else { return }
        switch sender.tag {
        case 1: mode = .window
        case 2: mode = .area
        default: mode = .screen
        }
        reloadTexts()
    }

    @objc private func cameraPicked() {
        Preferences.recordCamera = cameraPopup.indexOfSelectedItem > 0
        preview.cameraEnabled = Preferences.recordCamera
        preview.needsDisplay = true
    }

    @objc private func audioPicked() {
        Preferences.recordMicrophone = audioPopup.indexOfSelectedItem > 0
    }

    @objc private func qualityPicked() {
        Preferences.qualityIndex = qualityPopup.indexOfSelectedItem
        settingsQualityPopup.selectItem(at: Preferences.qualityIndex)
    }

    @objc private func settingsQualityChanged() {
        Preferences.qualityIndex = settingsQualityPopup.indexOfSelectedItem
        qualityPopup.selectItem(at: Preferences.qualityIndex)
    }

    @objc private func cameraLayoutChanged() {
        let positions: [CameraPosition] = [.topLeft, .topRight, .bottomLeft, .bottomRight]
        let index = min(max(positionPopup.indexOfSelectedItem, 0), positions.count - 1)
        Preferences.cameraPosition = positions[index]
        Preferences.cameraScale = cameraSizeSlider.doubleValue
        preview.cameraPosition = positions[index]
        preview.cameraScale = CGFloat(cameraSizeSlider.doubleValue)
        preview.needsDisplay = true
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
        guard let window = window else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Preferences.outputDirectory = url
            self?.outputPath.stringValue = url.path
        }
    }

    @objc private func minimizeChanged() { Preferences.minimizeOnRecord = minimizeCheckbox.state == .on }

    @objc private func autoUpdateChanged() {
        (NSApp.delegate as? AppDelegate)?.setAutomaticUpdates(autoUpdateCheckbox.state == .on)
    }

    @objc private func recordPressed() {
        if recorder.isRecording {
            setControls(enabled: false)
            statusLabel.stringValue = tr("record.saving")
            recordButton.isEnabled = false
            recorder.stop()
            return
        }
        startRecording()
    }

    private func startRecording() {
        guard !displays.isEmpty else { return }
        let cameraIndex = cameraPopup.indexOfSelectedItem
        let audioIndex = audioPopup.indexOfSelectedItem
        let wantsCamera = cameraIndex > 0 && cameraIndex - 1 < videoDevices.count
        let wantsAudio = audioIndex > 0 && audioIndex - 1 < audioDevices.count
        setControls(enabled: false)
        statusLabel.stringValue = tr("record.preparing")
        ScreenRecorder.requestPermissions(camera: wantsCamera, microphone: wantsAudio) { [weak self] granted in
            guard let self = self else { return }
            guard granted else {
                self.setControls(enabled: true)
                self.showRecordingError(RecorderError.cannotCreateWriter(tr("record.devicePermission")))
                return
            }
            let qualityIndex = min(max(Preferences.qualityIndex, 0), RecordingQuality.values.count - 1)
            let target = self.captureTarget()
            let configuration = RecordingConfiguration(
                displayID: target.displayID,
                audioDevice: wantsAudio ? self.audioDevices[safe: audioIndex - 1] : nil,
                cameraDevice: wantsCamera ? self.videoDevices[safe: cameraIndex - 1] : nil,
                cameraPosition: Preferences.cameraPosition,
                cameraScale: CGFloat(Preferences.cameraScale),
                quality: RecordingQuality.values[qualityIndex],
                capturesCursor: true,
                cropRect: target.crop
            )
            do {
                try self.recorder.start(configuration: configuration, outputURL: self.makeOutputURL())
            } catch {
                self.setControls(enabled: true)
                self.showRecordingError(error)
            }
        }
    }

    private func captureTarget() -> (displayID: CGDirectDisplayID, crop: CGRect?) {
        let fallback = displays[min(max(displayPopup.indexOfSelectedItem, 0), displays.count - 1)].id
        switch mode {
        case .screen:
            return (fallback, nil)
        case .area:
            return (fallback, areaCrop(displayID: fallback))
        case .window:
            windows = loadWindows()
            let title = displayPopup.titleOfSelectedItem
            let choice = windows.first { $0.title == title } ?? windows.first
            if let choice = choice, let crop = windowCrop(choice) {
                return crop
            }
            return (fallback, nil)
        }
    }

    private func areaCrop(displayID: CGDirectDisplayID) -> CGRect? {
        let bounds = CGDisplayBounds(displayID)
        let selection = preview.selection
        guard selection.width < 0.98 || selection.height < 0.98 else { return nil }
        return CGRect(
            x: (selection.origin.x * bounds.width).rounded(.down),
            y: (selection.origin.y * bounds.height).rounded(.down),
            width: max(2, (selection.width * bounds.width).rounded(.down)),
            height: max(2, (selection.height * bounds.height).rounded(.down))
        )
    }

    private func windowCrop(_ window: WindowChoice) -> (displayID: CGDirectDisplayID, crop: CGRect?)? {
        let center = CGPoint(x: window.bounds.midX, y: window.bounds.midY)
        for display in displays {
            let bounds = CGDisplayBounds(display.id)
            guard bounds.contains(center) else { continue }
            let local = window.bounds.offsetBy(dx: -bounds.origin.x, dy: -bounds.origin.y)
            let hit = local.intersection(CGRect(origin: .zero, size: bounds.size))
            guard hit.width >= 80, hit.height >= 80 else { return (display.id, nil) }
            return (display.id, hit.integral)
        }
        return nil
    }

    private func makeOutputURL() -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return Preferences.outputDirectory.appendingPathComponent("MaosRecord_\(formatter.string(from: Date())).mp4")
    }

    private func setControls(enabled: Bool) {
        displayPopup.isEnabled = enabled
        cameraPopup.isEnabled = enabled && !videoDevices.isEmpty
        audioPopup.isEnabled = enabled && !audioDevices.isEmpty
        qualityPopup.isEnabled = enabled
        screenModeButton.isEnabled = enabled
        windowModeButton.isEnabled = enabled
        areaModeButton.isEnabled = enabled
        for (item, button) in navButtons where item != .record {
            button.isEnabled = enabled
        }
        recordButton.isEnabled = enabled
    }

    func recorderDidStart(_ recorder: ScreenRecorder) {
        startedAt = Date()
        recordButton.image = RecordArt.stop
        recordButton.isEnabled = true
        recordCaption.stringValue = tr("record.stop")
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.updateStatus() }
        updateStatus()
        if Preferences.minimizeOnRecord { window?.miniaturize(nil) }
    }

    func recorder(_ recorder: ScreenRecorder, didFinish url: URL) {
        timer?.invalidate()
        timer = nil
        startedAt = nil
        lastSavedURL = url
        showFileButton.isHidden = false
        recordButton.image = RecordArt.start
        setControls(enabled: true)
        updateStatus()
        if terminatingAfterSave {
            NSApp.reply(toApplicationShouldTerminate: true)
        } else {
            window?.deminiaturize(nil)
            NSApp.requestUserAttention(.informationalRequest)
        }
    }

    func recorder(_ recorder: ScreenRecorder, didFail error: Error) {
        timer?.invalidate()
        timer = nil
        startedAt = nil
        recordButton.image = RecordArt.start
        setControls(enabled: true)
        updateStatus()
        if terminatingAfterSave {
            NSApp.reply(toApplicationShouldTerminate: true)
        } else {
            showRecordingError(error)
        }
    }

    private func updateStatus() {
        if let start = startedAt {
            let elapsed = Int(Date().timeIntervalSince(start))
            statusLabel.stringValue = String(format: tr("record.elapsed"), String(format: "%02d:%02d", elapsed / 60, elapsed % 60))
            recordCaption.stringValue = tr("record.stop")
        } else if lastSavedURL != nil {
            statusLabel.stringValue = tr("record.saved")
            recordCaption.stringValue = tr("record.start")
        } else {
            statusLabel.stringValue = ""
            recordCaption.stringValue = tr("record.start")
        }
    }

    private func showRecordingError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = tr("record.error")
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: tr("alert.ok"))
        if let window = window { alert.beginSheetModal(for: window) }
        else { alert.runModal() }
    }

    @objc private func showLastFile() {
        guard let url = lastSavedURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func stopForTermination() {
        terminatingAfterSave = true
        recorder.stop()
    }

    private func findTagline() -> NSTextField? {
        window?.contentView?.findText(identifier: "tagline")
    }

    private func languageButton() -> NSButton? {
        window?.contentView?.findButton(identifier: "language")
    }

    private func paint(_ view: NSView, _ color: NSColor) {
        guard let layer = view.layer else { return }
        let previous = NSAppearance.current
        NSAppearance.current = view.effectiveAppearance
        layer.backgroundColor = color.cgColor
        NSAppearance.current = previous
    }

    private func setButtonTitle(_ button: NSButton, _ title: String, color: NSColor, alignment: NSTextAlignment, weight: NSFont.Weight = .medium) {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        button.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: weight),
            .foregroundColor: color,
            .paragraphStyle: style
        ])
    }
}

private enum Chrome {
    static let window = adaptive(name: "window", light: rgb(0.95, 0.95, 0.96), dark: rgb(0.09, 0.10, 0.13))
    static let sidebar = adaptive(name: "sidebar", light: rgb(0.92, 0.93, 0.94), dark: rgb(0.07, 0.08, 0.11))
    static let card = adaptive(name: "card", light: rgb(1, 1, 1), dark: rgb(0.14, 0.15, 0.19))
    static let selected = adaptive(name: "selected", light: rgb(0.86, 0.88, 0.92), dark: rgb(0.18, 0.20, 0.26))
    static let accent = NSColor(srgbRed: 0.36, green: 0.48, blue: 0.98, alpha: 1)
    static let text = adaptive(name: "text", light: rgb(0.12, 0.13, 0.16), dark: rgb(0.93, 0.94, 0.96))
    static let secondary = adaptive(name: "secondary", light: rgb(0.38, 0.40, 0.46), dark: rgb(0.62, 0.65, 0.72))

    private static func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }

    private static func adaptive(name: String, light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: NSColor.Name("MaosRec.\(name)")) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }
}

private enum Glyph {
    enum Kind { case display, camera, mic, gear, sliders, window, area, help, about, language }

    static func image(_ kind: Kind) -> NSImage {
        let image = NSImage(size: NSSize(width: 16, height: 16))
        image.lockFocus()
        NSColor.black.setStroke()
        NSColor.black.setFill()
        let path = NSBezierPath()
        path.lineWidth = 1.4
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        switch kind {
        case .display:
            path.appendRoundedRect(NSRect(x: 1.5, y: 2.5, width: 13, height: 10), xRadius: 1.5, yRadius: 1.5)
            path.move(to: NSPoint(x: 5, y: 1.2))
            path.line(to: NSPoint(x: 11, y: 1.2))
        case .camera:
            path.appendRoundedRect(NSRect(x: 1.5, y: 3.5, width: 13, height: 9), xRadius: 1.5, yRadius: 1.5)
            path.appendOval(in: NSRect(x: 6, y: 5.5, width: 4, height: 4))
        case .mic:
            path.appendRoundedRect(NSRect(x: 6, y: 6, width: 4, height: 8), xRadius: 2, yRadius: 2)
            path.move(to: NSPoint(x: 4, y: 7))
            path.curve(to: NSPoint(x: 12, y: 7), controlPoint1: NSPoint(x: 4, y: 3), controlPoint2: NSPoint(x: 12, y: 3))
            path.move(to: NSPoint(x: 8, y: 3))
            path.line(to: NSPoint(x: 8, y: 1.2))
        case .gear:
            path.appendOval(in: NSRect(x: 5, y: 5, width: 6, height: 6))
            path.appendOval(in: NSRect(x: 2.2, y: 2.2, width: 11.6, height: 11.6))
        case .sliders:
            path.move(to: NSPoint(x: 2, y: 12))
            path.line(to: NSPoint(x: 14, y: 12))
            path.move(to: NSPoint(x: 2, y: 8))
            path.line(to: NSPoint(x: 14, y: 8))
            path.move(to: NSPoint(x: 2, y: 4))
            path.line(to: NSPoint(x: 14, y: 4))
        case .window:
            path.appendRoundedRect(NSRect(x: 2, y: 2, width: 12, height: 12), xRadius: 1.5, yRadius: 1.5)
            path.move(to: NSPoint(x: 2, y: 10.5))
            path.line(to: NSPoint(x: 14, y: 10.5))
        case .area:
            path.move(to: NSPoint(x: 2, y: 6))
            path.line(to: NSPoint(x: 2, y: 2))
            path.line(to: NSPoint(x: 6, y: 2))
            path.move(to: NSPoint(x: 10, y: 2))
            path.line(to: NSPoint(x: 14, y: 2))
            path.line(to: NSPoint(x: 14, y: 6))
            path.move(to: NSPoint(x: 14, y: 10))
            path.line(to: NSPoint(x: 14, y: 14))
            path.line(to: NSPoint(x: 10, y: 14))
            path.move(to: NSPoint(x: 6, y: 14))
            path.line(to: NSPoint(x: 2, y: 14))
            path.line(to: NSPoint(x: 2, y: 10))
        case .help:
            ("?" as NSString).draw(at: NSPoint(x: 4.5, y: 1), withAttributes: [.font: NSFont.systemFont(ofSize: 13, weight: .medium)])
        case .about:
            ("i" as NSString).draw(at: NSPoint(x: 6, y: 1), withAttributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold)])
        case .language:
            path.appendOval(in: NSRect(x: 1.5, y: 1.5, width: 13, height: 13))
            path.move(to: NSPoint(x: 8, y: 1.5))
            path.line(to: NSPoint(x: 8, y: 14.5))
            path.move(to: NSPoint(x: 1.5, y: 8))
            path.line(to: NSPoint(x: 14.5, y: 8))
        }
        if kind != .help && kind != .about { path.stroke() }
        image.unlockFocus()
        image.isTemplate = true
        return image
    }
}

private enum RecordArt {
    static let start = circle(recording: false)
    static let stop = circle(recording: true)

    private static func circle(recording: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 96, height: 96))
        image.lockFocus()
        NSColor(srgbRed: 0.22, green: 0.24, blue: 0.29, alpha: 1).setStroke()
        let ring = NSBezierPath(ovalIn: NSRect(x: 4, y: 4, width: 88, height: 88))
        ring.lineWidth = 7
        ring.stroke()
        NSColor(srgbRed: 0.93, green: 0.27, blue: 0.27, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 16, y: 16, width: 64, height: 64)).fill()
        if recording {
            NSColor.white.setFill()
            NSBezierPath(roundedRect: NSRect(x: 38, y: 38, width: 20, height: 20), xRadius: 3, yRadius: 3).fill()
        }
        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}

private final class FillView: NSView {
    var fill: NSColor
    init(fill: NSColor) {
        self.fill = fill
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    var onAppearanceChange: (() -> Void)?
    override var isOpaque: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        fill.setFill()
        dirtyRect.fill()
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        let previous = NSAppearance.current
        NSAppearance.current = effectiveAppearance
        layer?.backgroundColor = fill.cgColor
        NSAppearance.current = previous
        needsDisplay = true
        onAppearanceChange?()
    }
}

private final class MenuRow: NSView {
    let iconView = NSImageView()
    let titleLabel = NSTextField(labelWithString: "")
    let popup = NSPopUpButton(frame: .zero, pullsDown: false)

    init(icon: NSImage) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.backgroundColor = Chrome.card.cgColor
        iconView.image = icon
        iconView.contentTintColor = Chrome.secondary
        iconView.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = Chrome.text
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        popup.isBordered = false
        popup.font = .systemFont(ofSize: 12)
        popup.contentTintColor = Chrome.secondary
        popup.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)
        addSubview(titleLabel)
        addSubview(popup)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 58),
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            popup.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor, constant: -6),
            popup.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            popup.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: -2)
        ])
    }

    func refreshChrome() {
        let previous = NSAppearance.current
        NSAppearance.current = effectiveAppearance
        layer?.backgroundColor = Chrome.card.cgColor
        titleLabel.textColor = Chrome.text
        iconView.contentTintColor = Chrome.secondary
        popup.contentTintColor = Chrome.secondary
        NSAppearance.current = previous
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshChrome()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

private final class PreviewCanvas: NSView {
    enum Style { case screen, window, area }
    var style: Style = .screen
    var selection = CGRect(x: 0.12, y: 0.12, width: 0.76, height: 0.76)
    var cameraEnabled = false
    var cameraPosition = Preferences.cameraPosition
    var cameraScale = CGFloat(Preferences.cameraScale)
    private var dragAnchor: CGPoint?

    override var isOpaque: Bool { true }
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        Chrome.window.setFill()
        bounds.fill()
        let image = imageRect()
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: image, xRadius: 12, yRadius: 12).addClip()
        drawScene(in: image)
        if cameraEnabled { drawCameraBadge(in: image) }
        NSGraphicsContext.restoreGraphicsState()
        drawSelection(around: selectionFrame(in: image))
    }

    override func mouseDown(with event: NSEvent) {
        guard style == .area else { return }
        dragAnchor = convert(event.locationInWindow, from: nil)
        updateSelection(to: dragAnchor!)
    }

    override func mouseDragged(with event: NSEvent) {
        guard style == .area else { return }
        updateSelection(to: convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        dragAnchor = nil
    }

    private func imageRect() -> CGRect { bounds.insetBy(dx: 2, dy: 2) }

    private func selectionFrame(in image: CGRect) -> CGRect {
        switch style {
        case .screen:
            return image.insetBy(dx: 14, dy: 14)
        case .window:
            let width = image.width * 0.72
            let height = image.height * 0.64
            return CGRect(x: image.midX - width / 2, y: image.midY - height / 2, width: width, height: height)
        case .area:
            return CGRect(
                x: image.minX + selection.origin.x * image.width,
                y: image.minY + selection.origin.y * image.height,
                width: max(24, selection.width * image.width),
                height: max(24, selection.height * image.height)
            )
        }
    }

    private func updateSelection(to point: CGPoint) {
        guard let anchor = dragAnchor else { return }
        let image = imageRect()
        guard image.width > 1, image.height > 1 else { return }
        func unit(_ value: CGFloat, _ start: CGFloat, _ length: CGFloat) -> CGFloat {
            min(max((value - start) / length, 0), 1)
        }
        let ax = unit(anchor.x, image.minX, image.width)
        let ay = unit(anchor.y, image.minY, image.height)
        let bx = unit(point.x, image.minX, image.width)
        let by = unit(point.y, image.minY, image.height)
        var x = min(ax, bx)
        var y = min(ay, by)
        var width = max(abs(ax - bx), 0.12)
        var height = max(abs(ay - by), 0.12)
        if x + width > 1 { width = 1 - x }
        if y + height > 1 { height = 1 - y }
        selection = CGRect(x: x, y: y, width: width, height: height)
        needsDisplay = true
    }

    private func drawScene(in rect: CGRect) {
        NSGradient(colors: [
            NSColor(srgbRed: 0.97, green: 0.58, blue: 0.45, alpha: 1),
            NSColor(srgbRed: 0.36, green: 0.48, blue: 0.70, alpha: 1),
            NSColor(srgbRed: 0.10, green: 0.24, blue: 0.46, alpha: 1)
        ])?.draw(in: rect, angle: 90)
        NSColor(srgbRed: 0.07, green: 0.20, blue: 0.40, alpha: 1).setFill()
        CGRect(x: rect.minX, y: rect.minY + rect.height * 0.42, width: rect.width, height: rect.height * 0.58).fill()
        let island = NSBezierPath()
        island.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        island.line(to: CGPoint(x: rect.minX + rect.width * 0.16, y: rect.minY + rect.height * 0.58))
        island.line(to: CGPoint(x: rect.minX + rect.width * 0.46, y: rect.minY + rect.height * 0.20))
        island.line(to: CGPoint(x: rect.minX + rect.width * 0.74, y: rect.minY + rect.height * 0.52))
        island.line(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.40))
        island.line(to: CGPoint(x: rect.maxX, y: rect.maxY))
        island.close()
        NSColor(srgbRed: 0.24, green: 0.32, blue: 0.27, alpha: 1).setFill()
        island.fill()
    }

    private func drawCameraBadge(in image: CGRect) {
        let width = min(image.width * cameraScale, 120)
        let height = width * 9 / 16
        let margin: CGFloat = 22
        let origin: CGPoint
        switch cameraPosition {
        case .topLeft: origin = CGPoint(x: image.minX + margin, y: image.minY + margin)
        case .topRight: origin = CGPoint(x: image.maxX - width - margin, y: image.minY + margin)
        case .bottomLeft: origin = CGPoint(x: image.minX + margin, y: image.maxY - height - margin)
        case .bottomRight: origin = CGPoint(x: image.maxX - width - margin, y: image.maxY - height - margin)
        }
        let rect = CGRect(origin: origin, size: CGSize(width: width, height: height))
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        Chrome.accent.setFill()
        path.fill()
    }

    private func drawSelection(around frame: CGRect) {
        let border = NSBezierPath(rect: frame)
        NSColor(srgbRed: 0.95, green: 0.55, blue: 0.50, alpha: 1).setStroke()
        border.lineWidth = 1.5
        border.stroke()
        let handles = [
            CGPoint(x: frame.minX, y: frame.minY), CGPoint(x: frame.midX, y: frame.minY), CGPoint(x: frame.maxX, y: frame.minY),
            CGPoint(x: frame.minX, y: frame.midY), CGPoint(x: frame.maxX, y: frame.midY),
            CGPoint(x: frame.minX, y: frame.maxY), CGPoint(x: frame.midX, y: frame.maxY), CGPoint(x: frame.maxX, y: frame.maxY)
        ]
        for point in handles {
            let mark = CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)
            NSColor.white.setFill()
            NSBezierPath(rect: mark).fill()
            NSColor(srgbRed: 0.15, green: 0.16, blue: 0.2, alpha: 1).setStroke()
            let outline = NSBezierPath(rect: mark)
            outline.lineWidth = 1
            outline.stroke()
        }
    }
}

private extension NSView {
    func findText(identifier: String) -> NSTextField? {
        if let field = self as? NSTextField, self.identifier?.rawValue == identifier { return field }
        for child in subviews {
            if let found = child.findText(identifier: identifier) { return found }
        }
        return nil
    }

    func findButton(identifier: String) -> NSButton? {
        if let button = self as? NSButton, self.identifier?.rawValue == identifier { return button }
        for child in subviews {
            if let found = child.findButton(identifier: identifier) { return found }
        }
        return nil
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
