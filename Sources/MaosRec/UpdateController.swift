import AppKit
import CryptoKit
import Foundation

final class UpdateController {
    private struct Release: Decodable {
        struct Asset: Decodable {
            let name: String
            let downloadURL: String

            enum CodingKeys: String, CodingKey {
                case name
                case downloadURL = "browser_download_url"
            }
        }

        let tagName: String
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case assets
        }
    }

    private enum UpdateError: LocalizedError {
        case invalidResponse
        case invalidVersion
        case missingAssets
        case invalidDownloadURL
        case downloadFailed(String)
        case checksumMismatch
        case invalidPackage(String)
        case recordingIsActive
        case installationFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return local("GitHub returned an invalid update response.", "GitHub вернул некорректный ответ об обновлении.")
            case .invalidVersion:
                return local("The update version could not be determined.", "Не удалось определить версию обновления.")
            case .missingAssets:
                return local("The release is missing its ZIP or SHA256SUMS.txt file.", "В релизе отсутствует ZIP или SHA256SUMS.txt.")
            case .invalidDownloadURL:
                return local("The release contains an unsafe download URL.", "Релиз содержит небезопасную ссылку загрузки.")
            case .downloadFailed(let details):
                return local("The update could not be downloaded. \(details)", "Не удалось скачать обновление. \(details)")
            case .checksumMismatch:
                return local("The update checksum does not match. Installation was cancelled.", "Контрольная сумма обновления не совпадает. Установка отменена.")
            case .invalidPackage(let details):
                return local("The update package failed validation. \(details)", "Пакет обновления не прошёл проверку. \(details)")
            case .recordingIsActive:
                return local("Stop the recording before installing an update.", "Остановите запись перед установкой обновления.")
            case .installationFailed(let details):
                return local("The update could not be installed. \(details)", "Не удалось установить обновление. \(details)")
            }
        }
    }

    private lazy var releaseAPI: URL = {
        let configured = Bundle.main.object(forInfoDictionaryKey: "MaosRecGitHubRepository") as? String
        let slug = configured?.range(of: "^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", options: .regularExpression) != nil
            ? configured!
            : "noneandundefined/MaosRec"
        return URL(string: "https://api.github.com/repos/\(slug)/releases/latest")!
    }()
    private let zipName = "MaosRec-macOS-10.15-Intel.zip"
    private let checksumName = "SHA256SUMS.txt"
    private let session: URLSession
    private let worker = DispatchQueue(label: "com.maosrec.updater", qos: .userInitiated)
    private weak var presentingWindow: NSWindow?
    private let canInstall: () -> Bool
    private var isChecking = false
    private var isInstalling = false
    private var progressAlert: NSAlert?
    private var presentedVersion: String?

    init(presentingWindow: NSWindow, session: URLSession = .shared, canInstall: @escaping () -> Bool) {
        self.presentingWindow = presentingWindow
        self.session = session
        self.canInstall = canInstall
    }

    func checkAutomatically() { checkForUpdates(silent: true) }

    func checkForUpdates(silent: Bool) {
        guard !isChecking, !isInstalling else { return }
        if !silent { presentedVersion = nil }
        isChecking = true

        var request = URLRequest(url: releaseAPI)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("MaosRec/\(currentVersionString)", forHTTPHeaderField: "User-Agent")

        session.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isChecking = false
                if let error = error {
                    if !silent { self.showError(UpdateError.downloadFailed(error.localizedDescription)) }
                    return
                }
                guard let http = response as? HTTPURLResponse,
                      (200...299).contains(http.statusCode),
                      let data = data,
                      let release = try? JSONDecoder().decode(Release.self, from: data) else {
                    if !silent { self.showError(UpdateError.invalidResponse) }
                    return
                }
                guard let current = AppVersion(self.currentVersionString),
                      let latest = AppVersion(release.tagName) else {
                    if !silent { self.showError(UpdateError.invalidVersion) }
                    return
                }
                if latest > current {
                    self.showAvailableUpdate(release, version: latest.description)
                } else if !silent {
                    self.showUpToDate()
                }
            }
        }.resume()
    }

    private var currentVersionString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    private func showAvailableUpdate(_ release: Release, version: String) {
        guard presentedVersion != version else { return }
        presentedVersion = version
        NSApp.dockTile.badgeLabel = "↑"
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = local("Version \(version) is available", "Доступна версия \(version)")
        alert.informativeText = local(
            "MaosRec will download and verify the update, install it, and restart. Current version: \(currentVersionString).",
            "MaosRec скачает и проверит обновление, установит его и перезапустится. Текущая версия: \(currentVersionString)."
        )
        alert.addButton(withTitle: local("Update", "Обновить"))
        alert.addButton(withTitle: local("Later", "Позже"))
        present(alert) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.beginInstallation(release, version: version)
        }
    }

    private func showUpToDate() {
        NSApp.dockTile.badgeLabel = nil
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = local("MaosRec is up to date", "Установлена последняя версия MaosRec")
        alert.informativeText = local("Current version: \(currentVersionString).", "Текущая версия: \(currentVersionString).")
        alert.addButton(withTitle: local("OK", "Хорошо"))
        present(alert, completion: nil)
    }

    private func beginInstallation(_ release: Release, version: String) {
        guard canInstall() else { showError(UpdateError.recordingIsActive); return }
        guard !isInstalling else { return }
        guard let zipAsset = release.assets.first(where: { $0.name == zipName }),
              let checksumAsset = release.assets.first(where: { $0.name == checksumName }) else {
            showError(UpdateError.missingAssets)
            return
        }
        guard let zipURL = secureDownloadURL(zipAsset.downloadURL),
              let checksumURL = secureDownloadURL(checksumAsset.downloadURL) else {
            showError(UpdateError.invalidDownloadURL)
            return
        }

        isInstalling = true
        showProgress()
        fetchData(from: checksumURL) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure(let error): self.finishInstallation(with: error)
            case .success(let data): self.downloadArchive(from: zipURL, checksumData: data, version: version)
            }
        }
    }

    private func fetchData(from url: URL, completion: @escaping (Result<Data, Error>) -> Void) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("MaosRec/\(currentVersionString)", forHTTPHeaderField: "User-Agent")
        session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(UpdateError.downloadFailed(error.localizedDescription)))
                return
            }
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode),
                  let data = data, !data.isEmpty else {
                completion(.failure(UpdateError.downloadFailed("Invalid HTTP response.")))
                return
            }
            completion(.success(data))
        }.resume()
    }

    private func downloadArchive(from url: URL, checksumData: Data, version: String) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 120
        request.setValue("MaosRec/\(currentVersionString)", forHTTPHeaderField: "User-Agent")
        session.downloadTask(with: request) { [weak self] temporaryURL, response, error in
            guard let self = self else { return }
            if let error = error {
                self.finishInstallation(with: UpdateError.downloadFailed(error.localizedDescription))
                return
            }
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode), let temporaryURL = temporaryURL else {
                self.finishInstallation(with: UpdateError.downloadFailed("Invalid HTTP response."))
                return
            }
            do {
                let directory = FileManager.default.temporaryDirectory
                    .appendingPathComponent("MaosRecUpdate-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let archiveURL = directory.appendingPathComponent(self.zipName)
                try FileManager.default.copyItem(at: temporaryURL, to: archiveURL)
                self.worker.async {
                    do {
                        try self.validateAndInstall(archiveURL: archiveURL, checksumData: checksumData, expectedVersion: version, temporaryDirectory: directory)
                        try? FileManager.default.removeItem(at: directory)
                        self.finishInstallation(with: nil)
                    } catch {
                        try? FileManager.default.removeItem(at: directory)
                        self.finishInstallation(with: error)
                    }
                }
            } catch {
                self.finishInstallation(with: UpdateError.downloadFailed(error.localizedDescription))
            }
        }.resume()
    }

    private func validateAndInstall(archiveURL: URL, checksumData: Data, expectedVersion: String, temporaryDirectory: URL) throws {
        guard let checksumText = String(data: checksumData, encoding: .utf8),
              let expected = expectedChecksum(in: checksumText, filename: zipName) else {
            throw UpdateError.invalidPackage("SHA256SUMS.txt is malformed.")
        }
        guard try sha256(of: archiveURL) == expected else { throw UpdateError.checksumMismatch }

        let extracted = temporaryDirectory.appendingPathComponent("extracted", isDirectory: true)
        try FileManager.default.createDirectory(at: extracted, withIntermediateDirectories: true)
        try runProcess("/usr/bin/ditto", arguments: ["-x", "-k", archiveURL.path, extracted.path])
        let candidate = extracted.appendingPathComponent("MaosRec.app", isDirectory: true)
        guard let bundle = Bundle(url: candidate),
              bundle.bundleIdentifier == "com.maosrec.app",
              bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == expectedVersion,
              FileManager.default.isExecutableFile(atPath: candidate.appendingPathComponent("Contents/MacOS/MaosRec").path) else {
            throw UpdateError.invalidPackage("The application identity or version is invalid.")
        }
        try runProcess("/usr/bin/codesign", arguments: ["--verify", "--deep", "--strict", candidate.path])
        try replaceCurrentApplication(with: candidate)
    }

    private func replaceCurrentApplication(with candidate: URL) throws {
        let target = Bundle.main.bundleURL.standardizedFileURL
        guard target.pathExtension == "app", Bundle.main.bundleIdentifier == "com.maosrec.app" else {
            throw UpdateError.installationFailed("The running application path is invalid.")
        }
        let parent = target.deletingLastPathComponent()
        let nonce = UUID().uuidString
        let staged = parent.appendingPathComponent(".MaosRec-update-\(nonce).app")
        let backup = parent.appendingPathComponent(".MaosRec-backup-\(nonce).app")
        let command = """
        set -e
        /bin/rm -rf \(shellQuote(staged.path)) \(shellQuote(backup.path))
        /usr/bin/ditto \(shellQuote(candidate.path)) \(shellQuote(staged.path))
        /bin/mv \(shellQuote(target.path)) \(shellQuote(backup.path))
        if /bin/mv \(shellQuote(staged.path)) \(shellQuote(target.path)); then
          /bin/rm -rf \(shellQuote(backup.path))
        else
          /bin/mv \(shellQuote(backup.path)) \(shellQuote(target.path))
          exit 1
        fi
        """
        do { try runPrivileged(command) }
        catch { throw UpdateError.installationFailed(error.localizedDescription) }

        let relaunch = Process()
        relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
        relaunch.arguments = ["-c", "sleep 2; /usr/bin/open \(shellQuote(target.path))"]
        relaunch.standardOutput = FileHandle.nullDevice
        relaunch.standardError = FileHandle.nullDevice
        try relaunch.run()
    }

    private func expectedChecksum(in text: String, filename: String) -> String? {
        for line in text.components(separatedBy: .newlines) {
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard fields.count >= 2 else { continue }
            let listed = String(fields.last!).trimmingCharacters(in: CharacterSet(charactersIn: "*"))
            let checksum = String(fields[0]).lowercased()
            if listed == filename, checksum.count == 64,
               checksum.rangeOfCharacter(from: CharacterSet(charactersIn: "0123456789abcdef").inverted) == nil {
                return checksum
            }
        }
        return nil
    }

    private func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { handle.closeFile() }
        var hasher = SHA256()
        while true {
            let data = handle.readData(ofLength: 1_048_576)
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func secureDownloadURL(_ value: String) -> URL? {
        guard let url = URL(string: value), url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "github.com" else { return nil }
        return url
    }

    private func runProcess(_ executable: String, arguments: [String]) throws {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let details = String(data: data, encoding: .utf8) ?? "exit code \(process.terminationStatus)"
            throw UpdateError.invalidPackage(details.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private func runPrivileged(_ command: String) throws {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "do shell script \(appleScriptString(command)) with administrator privileges"]
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let details = String(data: data, encoding: .utf8) ?? "exit code \(process.terminationStatus)"
            throw UpdateError.installationFailed(details.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private func showProgress() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = local("Updating MaosRec", "Обновление MaosRec")
            alert.informativeText = local("Downloading and verifying the update…", "Загрузка и проверка обновления…")
            let progress = NSProgressIndicator(frame: NSRect(x: 0, y: 0, width: 240, height: 20))
            progress.style = .spinning
            progress.startAnimation(nil)
            alert.accessoryView = progress
            let button = alert.addButton(withTitle: local("Please wait…", "Подождите…"))
            button.isEnabled = false
            self.progressAlert = alert
            if let window = self.presentingWindow { alert.beginSheetModal(for: window, completionHandler: nil) }
        }
    }

    private func finishInstallation(with error: Error?) {
        DispatchQueue.main.async {
            self.isInstalling = false
            if let alert = self.progressAlert {
                alert.window.sheetParent?.endSheet(alert.window)
                alert.window.orderOut(nil)
                self.progressAlert = nil
            }
            if let error = error { self.showError(error) }
            else { NSApp.terminate(nil) }
        }
    }

    private func showError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.alertStyle = .warning
        alert.addButton(withTitle: local("OK", "Хорошо"))
        present(alert, completion: nil)
    }

    private func present(_ alert: NSAlert, completion: ((NSApplication.ModalResponse) -> Void)?) {
        if let window = presentingWindow { alert.beginSheetModal(for: window) { completion?($0) } }
        else { completion?(alert.runModal()) }
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func appleScriptString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }
}

private func local(_ english: String, _ russian: String) -> String {
    L10n.shared.languageCode == "ru" ? russian : english
}
