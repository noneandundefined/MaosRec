import AVFoundation
import CoreGraphics
import Foundation

enum AppLanguage: String, CaseIterable {
    case automatic
    case english
    case russian
}

enum CameraPosition: String, CaseIterable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
}

struct RecordingQuality: Equatable {
    let width: Int
    let height: Int
    let fps: Int
    let bitrate: Int

    static let economy = RecordingQuality(width: 960, height: 540, fps: 12, bitrate: 1_200_000)
    static let balanced = RecordingQuality(width: 1280, height: 720, fps: 15, bitrate: 2_000_000)
    static let smooth = RecordingQuality(width: 1280, height: 720, fps: 30, bitrate: 3_500_000)
    static let values = [economy, balanced, smooth]
}

struct RecordingConfiguration {
    let displayID: CGDirectDisplayID
    let audioDevice: AVCaptureDevice?
    let cameraDevice: AVCaptureDevice?
    let cameraPosition: CameraPosition
    let cameraScale: CGFloat
    let quality: RecordingQuality
    let capturesCursor: Bool
    /// Display points, origin at the top left. Nil records the whole display.
    let cropRect: CGRect?
}

enum Preferences {
    private static let defaults = UserDefaults.standard
    private enum Key {
        static let language = "language"
        static let outputDirectory = "outputDirectory"
        static let quality = "quality"
        static let cameraPosition = "cameraPosition"
        static let cameraScale = "cameraScale"
        static let recordCamera = "recordCamera"
        static let recordMicrophone = "recordMicrophone"
        static let autoUpdates = "autoUpdates"
        static let minimizeOnRecord = "minimizeOnRecord"
    }

    static var language: AppLanguage {
        get { AppLanguage(rawValue: defaults.string(forKey: Key.language) ?? "automatic") ?? .automatic }
        set { defaults.set(newValue.rawValue, forKey: Key.language) }
    }

    static var outputDirectory: URL {
        get {
            if let path = defaults.string(forKey: Key.outputDirectory), !path.isEmpty {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
            return FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first!
                .appendingPathComponent("Maos Record", isDirectory: true)
        }
        set { defaults.set(newValue.path, forKey: Key.outputDirectory) }
    }

    static var qualityIndex: Int {
        get { defaults.object(forKey: Key.quality) == nil ? 0 : defaults.integer(forKey: Key.quality) }
        set { defaults.set(newValue, forKey: Key.quality) }
    }

    static var cameraPosition: CameraPosition {
        get { CameraPosition(rawValue: defaults.string(forKey: Key.cameraPosition) ?? "bottomRight") ?? .bottomRight }
        set { defaults.set(newValue.rawValue, forKey: Key.cameraPosition) }
    }

    static var cameraScale: Double {
        get { defaults.object(forKey: Key.cameraScale) == nil ? 0.24 : defaults.double(forKey: Key.cameraScale) }
        set { defaults.set(newValue, forKey: Key.cameraScale) }
    }

    /// Off unless the user explicitly opts in. A missing key must stay screen-only.
    static var recordCamera: Bool {
        get { defaults.bool(forKey: Key.recordCamera) }
        set { defaults.set(newValue, forKey: Key.recordCamera) }
    }

    static var recordMicrophone: Bool {
        get { defaults.bool(forKey: Key.recordMicrophone) }
        set { defaults.set(newValue, forKey: Key.recordMicrophone) }
    }

    static var autoUpdates: Bool {
        get { defaults.object(forKey: Key.autoUpdates) == nil ? true : defaults.bool(forKey: Key.autoUpdates) }
        set { defaults.set(newValue, forKey: Key.autoUpdates) }
    }

    static var minimizeOnRecord: Bool {
        get { defaults.object(forKey: Key.minimizeOnRecord) == nil ? true : defaults.bool(forKey: Key.minimizeOnRecord) }
        set { defaults.set(newValue, forKey: Key.minimizeOnRecord) }
    }
}
