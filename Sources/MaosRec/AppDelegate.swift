import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var mainWindowController: MainWindowController!
    private var settingsWindowController: SettingsWindowController?
    private var updateController: UpdateController?
    private var updateTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = nil
        NSApp.applicationIconImage = AppIcon.make()
        buildMenu()
        mainWindowController = MainWindowController()
        mainWindowController.showWindow(nil)
        if let window = mainWindowController.window {
            updateController = UpdateController(presentingWindow: window) { [weak self] in
                self?.mainWindowController.isBusy != true
            }
        }
        NSApp.activate(ignoringOtherApps: true)

        if Preferences.autoUpdates {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.updateController?.checkAutomatically()
            }
            scheduleUpdateTimer()
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(languageChanged),
            name: .languageDidChange,
            object: nil
        )
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if mainWindowController?.isBusy == true {
            mainWindowController.stopForTermination()
            return .terminateLater
        }
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        updateTimer?.invalidate()
    }

    @objc private func languageChanged() {
        buildMenu()
        settingsWindowController?.reloadTexts()
    }

    private func buildMenu() {
        let root = NSMenu()
        let appItem = NSMenuItem()
        appItem.title = "Maos Record"
        root.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu

        let settings = NSMenuItem(title: tr("menu.settings"), action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(settings)

        let updates = NSMenuItem(title: tr("menu.updates"), action: #selector(checkForUpdates), keyEquivalent: "")
        updates.target = self
        appMenu.addItem(updates)
        appMenu.addItem(.separator())

        let quit = NSMenuItem(title: tr("menu.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenu.addItem(quit)
        NSApp.mainMenu = root
    }

    @objc func showSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController()
        }
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func checkForUpdates() {
        updateController?.checkForUpdates(silent: false)
    }

    func setAutomaticUpdates(_ enabled: Bool) {
        Preferences.autoUpdates = enabled
        updateTimer?.invalidate()
        updateTimer = nil
        if enabled {
            updateController?.checkAutomatically()
            scheduleUpdateTimer()
        }
    }

    private func scheduleUpdateTimer() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: 6 * 60 * 60, repeats: true) { [weak self] _ in
            guard Preferences.autoUpdates else { return }
            self?.updateController?.checkAutomatically()
        }
    }
}
