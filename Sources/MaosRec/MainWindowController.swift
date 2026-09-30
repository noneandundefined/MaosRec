import AppKit
import AVFoundation
import CoreGraphics

final class MainWindowController: NSWindowController, ScreenRecorderDelegate {
    private let recorder = ScreenRecorder()
    private var videoDevices: [AVCaptureDevice] = []
    private var audioDevices: [AVCaptureDevice] = []
    private var displays: [(id: CGDirectDisplayID, name: String)] = []
    private var timer: Timer?
    private var startedAt: Date?
    private var lastSavedURL: URL?
    private var terminatingAfterSave = false

    private let titleLabel = NSTextField(labelWithString: "MaosRec")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let screenTitle = NSTextField(labelWithString: "")
    private let cameraTitle = NSTextField(labelWithString: "")
    private let audioTitle = NSTextField(labelWithString: "")
    private let displayLabel = NSTextField(labelWithString: "")
    private let cameraDeviceLabel = NSTextField(labelWithString: "")
    private let audioDeviceLabel = NSTextField(labelWithString: "")
    private let positionLabel = NSTextField(labelWithString: "")
    private let sizeLabel = NSTextField(labelWithString: "")
    private let previewTitle = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let displayPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let cameraPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let audioPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let positionPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let cameraToggle = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let audioToggle = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let cameraSizeSlider = NSSlider(value: Preferences.cameraScale, minValue: 0.15, maxValue: 0.38, target: nil, action: nil)
    private let recordButton = NSButton(title: "", target: nil, action: nil)
    private let settingsButton = NSButton(title: "⚙", target: nil, action: nil)
    private let showFileButton = NSButton(title: "", target: nil, action: nil)
    private let preview = PreviewCanvas()

    var isRecording: Bool { recorder.isRecording }
    var isBusy: Bool { recorder.isBusy }

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "MaosRec"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 820, height: 540)
        window.center()
        super.init(window: window)
        recorder.delegate = self
        buildUI()
        reloadDevices()
        reloadTexts()
        NotificationCenter.default.addObserver(self, selector: #selector(reloadTexts), name: .languageDidChange, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildUI() {
        guard let content = window?.contentView else { return }
        let root = NSStackView()
        root.orientation = .horizontal
        root.spacing = 0
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            root.topAnchor.constraint(equalTo: content.topAnchor),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])

        let sidebar = NSVisualEffectView()
        sidebar.material = .sidebar
        sidebar.blendingMode = .behindWindow
        sidebar.state = .active
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        sidebar.widthAnchor.constraint(equalToConstant: 284).isActive = true
        root.addArrangedSubview(sidebar)

        let sideStack = NSStackView()
        sideStack.orientation = .vertical
        sideStack.alignment = .leading
        sideStack.spacing = 14
        sideStack.edgeInsets = NSEdgeInsets(top: 42, left: 20, bottom: 20, right: 20)
        sideStack.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(sideStack)
        NSLayoutConstraint.activate([
            sideStack.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor),
            sideStack.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            sideStack.topAnchor.constraint(equalTo: sidebar.topAnchor),
            sideStack.bottomAnchor.constraint(lessThanOrEqualTo: sidebar.bottomAnchor)
        ])

        titleLabel.font = .systemFont(ofSize: 25, weight: .bold)
        subtitleLabel.font = .systemFont(ofSize: 12, weight: .regular)
        subtitleLabel.textColor = .secondaryLabelColor
        sideStack.addArrangedSubview(titleLabel)
        sideStack.addArrangedSubview(subtitleLabel)
        sideStack.setCustomSpacing(24, after: subtitleLabel)

        sideStack.addArrangedSubview(sectionTitle(screenTitle))
        sideStack.addArrangedSubview(field(displayLabel, control: displayPopup))

        cameraToggle.target = self
        cameraToggle.action = #selector(sourceToggleChanged)
        sideStack.addArrangedSubview(toggleTitle(cameraTitle, toggle: cameraToggle))
        sideStack.addArrangedSubview(field(cameraDeviceLabel, control: cameraPopup))
        sideStack.addArrangedSubview(field(positionLabel, control: positionPopup))
        cameraSizeSlider.target = self
        cameraSizeSlider.action = #selector(cameraLayoutChanged)
        sideStack.addArrangedSubview(field(sizeLabel, control: cameraSizeSlider))

        audioToggle.target = self
        audioToggle.action = #selector(sourceToggleChanged)
        sideStack.addArrangedSubview(toggleTitle(audioTitle, toggle: audioToggle))
        sideStack.addArrangedSubview(field(audioDeviceLabel, control: audioPopup))

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        sideStack.addArrangedSubview(spacer)
        spacer.heightAnchor.constraint(greaterThanOrEqualToConstant: 4).isActive = true

        settingsButton.bezelStyle = .texturedRounded
        settingsButton.font = .systemFont(ofSize: 17)
        settingsButton.target = NSApp.delegate
        settingsButton.action = #selector(AppDelegate.showSettings)
        sideStack.addArrangedSubview(settingsButton)

        let main = NSView()
        root.addArrangedSubview(main)
        let mainStack = NSStackView()
        mainStack.orientation = .vertical
        mainStack.spacing = 14
        mainStack.edgeInsets = NSEdgeInsets(top: 42, left: 24, bottom: 22, right: 24)
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        main.addSubview(mainStack)
        NSLayoutConstraint.activate([
            mainStack.leadingAnchor.constraint(equalTo: main.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: main.trailingAnchor),
            mainStack.topAnchor.constraint(equalTo: main.topAnchor),
            mainStack.bottomAnchor.constraint(equalTo: main.bottomAnchor)
        ])

        previewTitle.font = .systemFont(ofSize: 14, weight: .semibold)
        mainStack.addArrangedSubview(previewTitle)
        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.heightAnchor.constraint(greaterThanOrEqualToConstant: 330).isActive = true
        mainStack.addArrangedSubview(preview)

        let bottom = NSStackView()
        bottom.orientation = .horizontal
        bottom.alignment = .centerY
        bottom.spacing = 12
        statusLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        statusLabel.textColor = .secondaryLabelColor
        bottom.addArrangedSubview(statusLabel)
        let flexible = NSView()
        bottom.addArrangedSubview(flexible)
        showFileButton.target = self
        showFileButton.action = #selector(showLastFile)
        showFileButton.isHidden = true
        bottom.addArrangedSubview(showFileButton)
        recordButton.bezelStyle = .rounded
        recordButton.controlSize = .large
        recordButton.font = .systemFont(ofSize: 14, weight: .semibold)
        recordButton.target = self
        recordButton.action = #selector(recordPressed)
        recordButton.keyEquivalent = "r"
        recordButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 158).isActive = true
        bottom.addArrangedSubview(recordButton)
        mainStack.addArrangedSubview(bottom)

        displayPopup.target = self
        displayPopup.action = #selector(displayChanged)
        positionPopup.target = self
        positionPopup.action = #selector(cameraLayoutChanged)
        sourceToggleChanged()
    }

    private func sectionTitle(_ label: NSTextField) -> NSView {
        label.font = .systemFont(ofSize: 11, weight: .bold)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func toggleTitle(_ label: NSTextField, toggle: NSButton) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.addArrangedSubview(sectionTitle(label))
        row.addArrangedSubview(NSView())
        row.addArrangedSubview(toggle)
        row.widthAnchor.constraint(equalToConstant: 244).isActive = true
        return row
    }

    private func field(_ label: NSTextField, control: NSView) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 5
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        stack.addArrangedSubview(label)
        control.translatesAutoresizingMaskIntoConstraints = false
        control.widthAnchor.constraint(equalToConstant: 244).isActive = true
        stack.addArrangedSubview(control)
        return stack
    }

    private func reloadDevices() {
        let cameraWasOn = videoDevices.isEmpty || cameraToggle.state == .on
        let audioWasOn = audioDevices.isEmpty || audioToggle.state == .on
        displays = NSScreen.screens.enumerated().compactMap { index, screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return (number.uint32Value, "\(tr("source.display")) \(index + 1) — \(Int(screen.frame.width))×\(Int(screen.frame.height))")
        }
        displayPopup.removeAllItems()
        displayPopup.addItems(withTitles: displays.map(\.name))

        videoDevices = ScreenRecorder.videoDevices
        cameraPopup.removeAllItems()
        cameraPopup.addItems(withTitles: videoDevices.map(\.localizedName))
        cameraToggle.state = !videoDevices.isEmpty && cameraWasOn ? .on : .off

        audioDevices = ScreenRecorder.audioDevices
        audioPopup.removeAllItems()
        audioPopup.addItems(withTitles: audioDevices.map(\.localizedName))
        audioToggle.state = !audioDevices.isEmpty && audioWasOn ? .on : .off
        sourceToggleChanged()
    }

    @objc private func reloadTexts() {
        subtitleLabel.stringValue = tr("app.subtitle")
        screenTitle.stringValue = tr("source.screen")
        cameraTitle.stringValue = tr("source.camera")
        audioTitle.stringValue = tr("source.audio")
        displayLabel.stringValue = tr("source.display")
        cameraDeviceLabel.stringValue = tr("source.device")
        audioDeviceLabel.stringValue = tr("source.device")
        positionLabel.stringValue = tr("camera.position")
        sizeLabel.stringValue = tr("camera.size")
        previewTitle.stringValue = tr("preview.title")
        showFileButton.title = tr("menu.showFile")
        positionPopup.removeAllItems()
        positionPopup.addItems(withTitles: [tr("camera.topLeft"), tr("camera.topRight"), tr("camera.bottomLeft"), tr("camera.bottomRight")])
        let positions: [CameraPosition] = [.topLeft, .topRight, .bottomLeft, .bottomRight]
        positionPopup.selectItem(at: positions.firstIndex(of: Preferences.cameraPosition) ?? 3)
        updateStatus()
        reloadDevices()
        preview.needsDisplay = true
    }

    @objc private func sourceToggleChanged() {
        cameraPopup.isEnabled = cameraToggle.state == .on && !videoDevices.isEmpty
        positionPopup.isEnabled = cameraPopup.isEnabled
        cameraSizeSlider.isEnabled = cameraPopup.isEnabled
        audioPopup.isEnabled = audioToggle.state == .on && !audioDevices.isEmpty
        preview.cameraEnabled = cameraPopup.isEnabled
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

    @objc private func displayChanged() { preview.needsDisplay = true }

    @objc private func recordPressed() {
        if recorder.isRecording {
            setControls(enabled: false)
            statusLabel.stringValue = tr("record.saving")
            recorder.stop()
            return
        }
        startRecording()
    }

    private func startRecording() {
        guard !displays.isEmpty else { return }
        let wantsCamera = cameraToggle.state == .on && !videoDevices.isEmpty
        let wantsAudio = audioToggle.state == .on && !audioDevices.isEmpty
        setControls(enabled: false)
        statusLabel.stringValue = tr("record.preparing")

        ScreenRecorder.requestPermissions(camera: wantsCamera, microphone: wantsAudio) { [weak self] granted in
            guard let self = self else { return }
            guard granted else {
                self.setControls(enabled: true)
                self.presentError(RecorderError.cannotCreateWriter(tr("record.devicePermission")))
                return
            }
            let qualityIndex = min(max(Preferences.qualityIndex, 0), RecordingQuality.values.count - 1)
            let displayIndex = min(max(self.displayPopup.indexOfSelectedItem, 0), self.displays.count - 1)
            let configuration = RecordingConfiguration(
                displayID: self.displays[displayIndex].id,
                audioDevice: wantsAudio ? self.audioDevices[safe: self.audioPopup.indexOfSelectedItem] : nil,
                cameraDevice: wantsCamera ? self.videoDevices[safe: self.cameraPopup.indexOfSelectedItem] : nil,
                cameraPosition: Preferences.cameraPosition,
                cameraScale: CGFloat(Preferences.cameraScale),
                quality: RecordingQuality.values[qualityIndex],
                capturesCursor: true
            )
            do {
                try self.recorder.start(configuration: configuration, outputURL: self.makeOutputURL())
            } catch {
                self.setControls(enabled: true)
                self.presentError(error)
            }
        }
    }

    private func makeOutputURL() -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return Preferences.outputDirectory.appendingPathComponent("MaosRec_\(formatter.string(from: Date())).mp4")
    }

    private func setControls(enabled: Bool) {
        displayPopup.isEnabled = enabled
        cameraToggle.isEnabled = enabled && !videoDevices.isEmpty
        audioToggle.isEnabled = enabled && !audioDevices.isEmpty
        settingsButton.isEnabled = enabled
        if enabled { sourceToggleChanged() }
        else {
            cameraPopup.isEnabled = false
            audioPopup.isEnabled = false
            positionPopup.isEnabled = false
            cameraSizeSlider.isEnabled = false
        }
        recordButton.isEnabled = enabled
    }

    func recorderDidStart(_ recorder: ScreenRecorder) {
        startedAt = Date()
        recordButton.title = tr("record.stop")
        recordButton.contentTintColor = .systemRed
        recordButton.isEnabled = true
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.updateStatus() }
        updateStatus()
        if Preferences.minimizeOnRecord { window?.miniaturize(nil) }
    }

    func recorder(_ recorder: ScreenRecorder, didFinish url: URL) {
        timer?.invalidate(); timer = nil; startedAt = nil
        lastSavedURL = url
        showFileButton.isHidden = false
        recordButton.contentTintColor = nil
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
        timer?.invalidate(); timer = nil; startedAt = nil
        recordButton.contentTintColor = nil
        setControls(enabled: true)
        updateStatus()
        if terminatingAfterSave {
            NSApp.reply(toApplicationShouldTerminate: true)
        } else {
            presentError(error)
        }
    }

    private func updateStatus() {
        if let start = startedAt {
            let elapsed = Int(Date().timeIntervalSince(start))
            statusLabel.stringValue = String(format: tr("record.elapsed"), String(format: "%02d:%02d", elapsed / 60, elapsed % 60))
            recordButton.title = tr("record.stop")
        } else if lastSavedURL != nil {
            statusLabel.stringValue = tr("record.saved")
            recordButton.title = tr("record.start")
        } else {
            statusLabel.stringValue = tr("record.ready")
            recordButton.title = tr("record.start")
        }
    }

    private func presentError(_ error: Error) {
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

private final class PreviewCanvas: NSView {
    var cameraEnabled = false { didSet { needsDisplay = true } }
    var cameraPosition = Preferences.cameraPosition
    var cameraScale = CGFloat(Preferences.cameraScale)

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let outer = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: outer, xRadius: 12, yRadius: 12)
        NSColor(calibratedWhite: 0.07, alpha: 1).setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.lineWidth = 1
        path.stroke()

        let icon = "▣"
        let iconAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 42, weight: .ultraLight),
            .foregroundColor: NSColor(calibratedWhite: 0.55, alpha: 1)
        ]
        let iconSize = icon.size(withAttributes: iconAttributes)
        icon.draw(at: CGPoint(x: bounds.midX - iconSize.width / 2, y: bounds.midY - 46), withAttributes: iconAttributes)
        let hint = tr("preview.hint")
        let hintAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor(calibratedWhite: 0.55, alpha: 1)
        ]
        let hintSize = hint.size(withAttributes: hintAttributes)
        hint.draw(at: CGPoint(x: bounds.midX - hintSize.width / 2, y: bounds.midY + 15), withAttributes: hintAttributes)

        guard cameraEnabled else { return }
        let margin: CGFloat = 18
        let width = min(bounds.width * cameraScale, 230)
        let height = width * 9 / 16
        let x: CGFloat
        let y: CGFloat
        switch cameraPosition {
        case .topLeft: x = margin; y = margin
        case .topRight: x = bounds.width - width - margin; y = margin
        case .bottomLeft: x = margin; y = bounds.height - height - margin
        case .bottomRight: x = bounds.width - width - margin; y = bounds.height - height - margin
        }
        let rect = CGRect(x: x, y: y, width: width, height: height)
        let camera = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        NSColor.systemBlue.withAlphaComponent(0.82).setFill()
        camera.fill()
        NSColor.white.withAlphaComponent(0.8).setStroke()
        camera.lineWidth = 2
        camera.stroke()
        let text = tr("preview.camera")
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        let size = text.size(withAttributes: attrs)
        text.draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: attrs)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
