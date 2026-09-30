import AppKit
import AVFoundation
import CoreGraphics

final class MainWindowController: NSWindowController, ScreenRecorderDelegate {
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
    private var mode: CaptureMode = .screen
    private var timer: Timer?
    private var startedAt: Date?
    private var lastSavedURL: URL?
    private var terminatingAfterSave = false

    private let tabs = NSTabView()
    private let recordItem = NSTabViewItem()
    private let settingsItem = NSTabViewItem()

    private let screenModeButton = NSButton(radioButtonWithTitle: "", target: nil, action: nil)
    private let windowModeButton = NSButton(radioButtonWithTitle: "", target: nil, action: nil)
    private let areaModeButton = NSButton(radioButtonWithTitle: "", target: nil, action: nil)
    private let sourceLabel = NSTextField(labelWithString: "")
    private let cameraLabel = NSTextField(labelWithString: "")
    private let audioLabel = NSTextField(labelWithString: "")
    private let formatLabel = NSTextField(labelWithString: "")
    private let qualityLabel = NSTextField(labelWithString: "")
    private let positionLabel = NSTextField(labelWithString: "")
    private let sizeLabel = NSTextField(labelWithString: "")
    private let displayPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let cameraPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let audioPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let formatPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let qualityPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let positionPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let cameraSizeSlider = NSSlider(value: Preferences.cameraScale, minValue: 0.15, maxValue: 0.38, target: nil, action: nil)
    private let modeHint = NSTextField(wrappingLabelWithString: "")
    private let areaPicker = AreaPicker()
    private let recordButton = NSButton(title: "", target: nil, action: nil)
    private let recordCaption = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let showFileButton = NSButton(title: "", target: nil, action: nil)

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
    private let helpText = NSTextField(wrappingLabelWithString: "")
    private let aboutVersion = NSTextField(labelWithString: "")

    var isRecording: Bool { recorder.isRecording }
    var isBusy: Bool { recorder.isBusy }

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Maos Record"
        window.isOpaque = true
        window.minSize = NSSize(width: 480, height: 560)
        window.center()
        super.init(window: window)
        recorder.delegate = self
        buildUI()
        reloadDevices()
        reloadTexts()
        NotificationCenter.default.addObserver(self, selector: #selector(reloadTexts), name: .languageDidChange, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func showSettingsPage() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        tabs.selectTabViewItem(settingsItem)
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }
        let record = NSView()
        let settings = NSView()
        recordItem.view = record
        settingsItem.view = settings
        tabs.addTabViewItem(recordItem)
        tabs.addTabViewItem(settingsItem)
        tabs.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(tabs)
        NSLayoutConstraint.activate([
            tabs.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            tabs.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            tabs.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            tabs.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16)
        ])
        buildRecord(record)
        buildSettings(settings)
    }

    private func buildRecord(_ record: NSView) {
        let form = NSStackView()
        form.orientation = .vertical
        form.alignment = .leading
        form.spacing = 12
        form.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        form.translatesAutoresizingMaskIntoConstraints = false
        record.addSubview(form)

        for button in [screenModeButton, windowModeButton, areaModeButton] {
            button.target = self
            button.action = #selector(modePressed(_:))
        }
        screenModeButton.state = .on
        let modes = NSStackView(views: [screenModeButton, windowModeButton, areaModeButton])
        modes.orientation = .horizontal
        modes.spacing = 16
        form.addArrangedSubview(modes)

        cameraPopup.target = self
        cameraPopup.action = #selector(cameraPicked)
        audioPopup.target = self
        audioPopup.action = #selector(audioPicked)
        qualityPopup.target = self
        qualityPopup.action = #selector(qualityPicked)
        positionPopup.target = self
        positionPopup.action = #selector(cameraLayoutChanged)
        cameraSizeSlider.target = self
        cameraSizeSlider.action = #selector(cameraLayoutChanged)

        form.addArrangedSubview(row(sourceLabel, displayPopup))
        form.addArrangedSubview(row(cameraLabel, cameraPopup))
        form.addArrangedSubview(row(positionLabel, positionPopup))
        form.addArrangedSubview(row(sizeLabel, cameraSizeSlider))
        form.addArrangedSubview(row(audioLabel, audioPopup))
        form.addArrangedSubview(row(formatLabel, formatPopup))
        form.addArrangedSubview(row(qualityLabel, qualityPopup))

        modeHint.textColor = .secondaryLabelColor
        modeHint.maximumNumberOfLines = 2
        modeHint.preferredMaxLayoutWidth = 440
        form.addArrangedSubview(modeHint)

        areaPicker.translatesAutoresizingMaskIntoConstraints = false
        areaPicker.heightAnchor.constraint(equalToConstant: 140).isActive = true
        form.addArrangedSubview(areaPicker)
        areaPicker.widthAnchor.constraint(equalTo: form.widthAnchor, constant: -32).isActive = true

        recordButton.image = RecordArt.start
        recordButton.imagePosition = .imageOnly
        recordButton.isBordered = false
        recordButton.target = self
        recordButton.action = #selector(recordPressed)
        recordButton.keyEquivalent = "r"
        recordButton.keyEquivalentModifierMask = .command
        recordButton.translatesAutoresizingMaskIntoConstraints = false
        recordButton.widthAnchor.constraint(equalToConstant: 96).isActive = true
        recordButton.heightAnchor.constraint(equalToConstant: 96).isActive = true
        recordCaption.alignment = .center
        statusLabel.alignment = .center
        statusLabel.textColor = .secondaryLabelColor
        showFileButton.target = self
        showFileButton.action = #selector(showLastFile)
        showFileButton.isHidden = true
        showFileButton.bezelStyle = .rounded

        let recordBlock = NSStackView(views: [recordButton, recordCaption, statusLabel, showFileButton])
        recordBlock.orientation = .vertical
        recordBlock.alignment = .centerX
        recordBlock.spacing = 6
        form.addArrangedSubview(recordBlock)
        recordBlock.widthAnchor.constraint(equalTo: form.widthAnchor, constant: -32).isActive = true

        NSLayoutConstraint.activate([
            form.leadingAnchor.constraint(equalTo: record.leadingAnchor),
            form.trailingAnchor.constraint(equalTo: record.trailingAnchor),
            form.topAnchor.constraint(equalTo: record.topAnchor),
            form.bottomAnchor.constraint(lessThanOrEqualTo: record.bottomAnchor)
        ])
        updateModeVisibility()
    }

    private func buildSettings(_ settings: NSView) {
        let form = NSStackView()
        form.orientation = .vertical
        form.alignment = .leading
        form.spacing = 12
        form.edgeInsets = NSEdgeInsets(top: 16, left: 8, bottom: 16, right: 16)
        form.translatesAutoresizingMaskIntoConstraints = false
        settings.addSubview(form)

        settingsHeading.font = .systemFont(ofSize: 15, weight: .semibold)
        updatesHeading.font = .systemFont(ofSize: 13, weight: .semibold)
        languagePopup.target = self
        languagePopup.action = #selector(languageChanged)
        chooseButton.target = self
        chooseButton.action = #selector(chooseOutput)
        chooseButton.bezelStyle = .rounded
        settingsQualityPopup.target = self
        settingsQualityPopup.action = #selector(settingsQualityChanged)
        minimizeCheckbox.target = self
        minimizeCheckbox.action = #selector(minimizeChanged)
        autoUpdateCheckbox.target = self
        autoUpdateCheckbox.action = #selector(autoUpdateChanged)
        checkButton.target = NSApp.delegate
        checkButton.action = #selector(AppDelegate.checkForUpdates)
        checkButton.bezelStyle = .rounded
        outputPath.lineBreakMode = .byTruncatingMiddle
        outputPath.textColor = .secondaryLabelColor
        themeValue.textColor = .secondaryLabelColor
        helpText.textColor = .secondaryLabelColor
        helpText.maximumNumberOfLines = 0
        helpText.preferredMaxLayoutWidth = 440
        aboutVersion.textColor = .secondaryLabelColor

        let outputRow = NSStackView(views: [outputPath, chooseButton])
        outputRow.orientation = .horizontal
        form.addArrangedSubview(settingsHeading)
        form.addArrangedSubview(row(languageLabel, languagePopup))
        form.addArrangedSubview(row(outputLabel, outputRow))
        form.addArrangedSubview(row(themeLabel, themeValue))
        form.addArrangedSubview(row(settingsQualityLabel, settingsQualityPopup))
        form.addArrangedSubview(minimizeCheckbox)
        form.addArrangedSubview(updatesHeading)
        form.addArrangedSubview(autoUpdateCheckbox)
        form.addArrangedSubview(checkButton)
        form.addArrangedSubview(helpText)
        form.addArrangedSubview(aboutVersion)

        NSLayoutConstraint.activate([
            form.leadingAnchor.constraint(equalTo: settings.leadingAnchor),
            form.trailingAnchor.constraint(equalTo: settings.trailingAnchor),
            form.topAnchor.constraint(equalTo: settings.topAnchor),
            form.bottomAnchor.constraint(lessThanOrEqualTo: settings.bottomAnchor)
        ])
    }

    private func row(_ label: NSTextField, _ control: NSView) -> NSView {
        label.alignment = .right
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: 130).isActive = true
        control.translatesAutoresizingMaskIntoConstraints = false
        control.widthAnchor.constraint(greaterThanOrEqualToConstant: 240).isActive = true
        let line = NSStackView(views: [label, control])
        line.orientation = .horizontal
        line.alignment = .centerY
        line.spacing = 8
        return line
    }

    @objc private func reloadTexts() {
        recordItem.label = tr("nav.record")
        settingsItem.label = tr("nav.settings")
        screenModeButton.title = tr("mode.screen")
        windowModeButton.title = tr("mode.window")
        areaModeButton.title = tr("mode.area")
        sourceLabel.stringValue = mode == .window ? tr("field.window") : tr("field.screen")
        cameraLabel.stringValue = tr("field.camera")
        audioLabel.stringValue = tr("field.microphone")
        formatLabel.stringValue = tr("field.format")
        qualityLabel.stringValue = tr("field.quality")
        positionLabel.stringValue = tr("camera.position")
        sizeLabel.stringValue = tr("camera.size")
        updateModeVisibility()
        settingsHeading.stringValue = tr("settings.general")
        languageLabel.stringValue = tr("settings.language")
        outputLabel.stringValue = tr("settings.output")
        chooseButton.title = tr("settings.choose")
        themeLabel.stringValue = tr("settings.theme")
        themeValue.stringValue = tr("settings.theme.system")
        settingsQualityLabel.stringValue = tr("settings.quality")
        minimizeCheckbox.title = tr("settings.minimize")
        updatesHeading.stringValue = tr("settings.updates")
        autoUpdateCheckbox.title = tr("settings.autoUpdates")
        checkButton.title = tr("settings.check")
        helpText.stringValue = tr("help.body")
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        aboutVersion.stringValue = String(format: tr("about.version"), version)
        showFileButton.title = tr("menu.showFile")
        languagePopup.removeAllItems()
        languagePopup.addItems(withTitles: [tr("settings.language.auto"), tr("settings.language.en"), tr("settings.language.ru")])
        let languages: [AppLanguage] = [.automatic, .english, .russian]
        languagePopup.selectItem(at: languages.firstIndex(of: Preferences.language) ?? 0)
        reloadDevices()
        updateStatus()
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
        settingsQualityPopup.removeAllItems()
        settingsQualityPopup.addItems(withTitles: [tr("settings.quality.economy"), tr("settings.quality.balanced"), tr("settings.quality.smooth")])
        settingsQualityPopup.selectItem(at: min(max(Preferences.qualityIndex, 0), 2))
        formatPopup.removeAllItems()
        formatPopup.addItem(withTitle: tr("format.mp4"))
        positionPopup.removeAllItems()
        positionPopup.addItems(withTitles: [tr("camera.topLeft"), tr("camera.topRight"), tr("camera.bottomLeft"), tr("camera.bottomRight")])
        let positions: [CameraPosition] = [.topLeft, .topRight, .bottomLeft, .bottomRight]
        positionPopup.selectItem(at: positions.firstIndex(of: Preferences.cameraPosition) ?? 3)
        outputPath.stringValue = Preferences.outputDirectory.path
        minimizeCheckbox.state = Preferences.minimizeOnRecord ? .on : .off
        autoUpdateCheckbox.state = Preferences.autoUpdates ? .on : .off
        positionPopup.isEnabled = cameraPopup.indexOfSelectedItem > 0
        cameraSizeSlider.isEnabled = cameraPopup.indexOfSelectedItem > 0
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
                displayPopup.selectItem(at: min(max(preferredIndex, 0), windows.count - 1))
            }
        } else if displays.count <= 1 {
            displayPopup.addItem(withTitle: tr("source.entire"))
        } else {
            displayPopup.addItems(withTitles: displays.map(\.name))
            displayPopup.selectItem(at: min(max(preferredIndex, 0), max(displays.count - 1, 0)))
        }
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

    private func updateModeVisibility() {
        screenModeButton.state = mode == .screen ? .on : .off
        windowModeButton.state = mode == .window ? .on : .off
        areaModeButton.state = mode == .area ? .on : .off
        sourceLabel.stringValue = mode == .window ? tr("field.window") : tr("field.screen")
        areaPicker.isHidden = mode != .area
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
    }

    @objc private func modePressed(_ sender: NSButton) {
        guard !recorder.isRecording else { return }
        if sender == windowModeButton { mode = .window }
        else if sender == areaModeButton { mode = .area }
        else { mode = .screen }
        reloadScreenPopup(preferredIndex: 0)
        updateModeVisibility()
    }

    @objc private func cameraPicked() {
        Preferences.recordCamera = cameraPopup.indexOfSelectedItem > 0
        positionPopup.isEnabled = Preferences.recordCamera
        cameraSizeSlider.isEnabled = Preferences.recordCamera
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
        let fallback = displays[min(max(displayPopup.indexOfSelectedItem, 0), max(displays.count - 1, 0))].id
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
        let selection = areaPicker.selection
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
        formatPopup.isEnabled = enabled
        positionPopup.isEnabled = enabled && cameraPopup.indexOfSelectedItem > 0
        cameraSizeSlider.isEnabled = enabled && cameraPopup.indexOfSelectedItem > 0
        screenModeButton.isEnabled = enabled
        windowModeButton.isEnabled = enabled
        areaModeButton.isEnabled = enabled
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

private final class AreaPicker: NSView {
    var selection = CGRect(x: 0.12, y: 0.12, width: 0.76, height: 0.76)
    private var dragAnchor: CGPoint?

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        bounds.fill()
        NSColor.separatorColor.setStroke()
        let border = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1
        border.stroke()
        let frame = CGRect(
            x: selection.origin.x * bounds.width,
            y: selection.origin.y * bounds.height,
            width: max(24, selection.width * bounds.width),
            height: max(24, selection.height * bounds.height)
        )
        NSColor.controlAccentColor.setStroke()
        let mark = NSBezierPath(rect: frame)
        mark.lineWidth = 2
        mark.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        dragAnchor = convert(event.locationInWindow, from: nil)
        updateSelection(to: dragAnchor!)
    }

    override func mouseDragged(with event: NSEvent) {
        updateSelection(to: convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        dragAnchor = nil
    }

    private func updateSelection(to point: CGPoint) {
        guard let anchor = dragAnchor, bounds.width > 1, bounds.height > 1 else { return }
        func unit(_ value: CGFloat, _ length: CGFloat) -> CGFloat { min(max(value / length, 0), 1) }
        let ax = unit(anchor.x, bounds.width)
        let ay = unit(anchor.y, bounds.height)
        let bx = unit(point.x, bounds.width)
        let by = unit(point.y, bounds.height)
        var x = min(ax, bx)
        var y = min(ay, by)
        var width = max(abs(ax - bx), 0.12)
        var height = max(abs(ay - by), 0.12)
        if x + width > 1 { width = 1 - x }
        if y + height > 1 { height = 1 - y }
        selection = CGRect(x: x, y: y, width: width, height: height)
        needsDisplay = true
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
