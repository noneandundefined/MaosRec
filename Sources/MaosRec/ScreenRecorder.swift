import AppKit
import AVFoundation
import CoreGraphics
import CoreImage
import CoreMedia
import CoreVideo

protocol ScreenRecorderDelegate: AnyObject {
    func recorderDidStart(_ recorder: ScreenRecorder)
    func recorder(_ recorder: ScreenRecorder, didFinish url: URL)
    func recorder(_ recorder: ScreenRecorder, didFail error: Error)
}

enum RecorderError: LocalizedError {
    case screenPermissionDenied
    case displayUnavailable
    case cannotAddScreenInput
    case cannotAddOutput
    case cannotCreateWriter(String)
    case cameraUnavailable
    case microphoneUnavailable

    var errorDescription: String? {
        switch self {
        case .screenPermissionDenied: return tr("record.permission")
        case .displayUnavailable: return tr("error.display")
        case .cannotAddScreenInput: return tr("error.screenInput")
        case .cannotAddOutput: return tr("error.output")
        case .cannotCreateWriter(let message): return message
        case .cameraUnavailable: return tr("error.camera")
        case .microphoneUnavailable: return tr("error.microphone")
        }
    }
}

final class ScreenRecorder: NSObject {
    weak var delegate: ScreenRecorderDelegate?

    private let screenSession = AVCaptureSession()
    private var cameraSession: AVCaptureSession?
    private let screenOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private let cameraOutput = AVCaptureVideoDataOutput()
    private let writerQueue = DispatchQueue(label: "com.maosrec.writer", qos: .userInitiated)
    private let cameraQueue = DispatchQueue(label: "com.maosrec.camera", qos: .userInitiated)
    private let cameraLock = NSLock()
    private lazy var ciContext = CIContext(options: [.cacheIntermediates: false])

    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var pixelAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var latestCameraBuffer: CVPixelBuffer?
    private var configuration: RecordingConfiguration?
    private var outputURL: URL?
    private var outputSize = CGSize(width: 1280, height: 720)
    private var framesPerSecond = 15
    private let timeline = RecordingTimeline()
    private var startedWriting = false
    private var isStopping = false

    var isRecording: Bool { writer != nil && !isStopping }
    var isBusy: Bool { writer != nil }

    static var videoDevices: [AVCaptureDevice] {
        var deviceTypes: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera]
        if #available(macOS 14.0, *) {
            deviceTypes.append(.external)
        } else {
            deviceTypes.append(.externalUnknown)
        }

        return AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .video,
            position: .unspecified
        ).devices.sorted { $0.localizedName < $1.localizedName }
    }

    static var audioDevices: [AVCaptureDevice] {
        if #available(macOS 14.0, *) {
            return AVCaptureDevice.DiscoverySession(
                deviceTypes: [.microphone],
                mediaType: .audio,
                position: .unspecified
            ).devices.sorted { $0.localizedName < $1.localizedName }
        }

        return AVCaptureDevice.devices(for: .audio)
            .sorted { $0.localizedName < $1.localizedName }
    }

    static func requestPermissions(camera: Bool, microphone: Bool, completion: @escaping (Bool) -> Void) {
        let group = DispatchGroup()
        let lock = NSLock()
        var granted = true

        func request(_ type: AVMediaType, needed: Bool) {
            guard needed else { return }
            switch AVCaptureDevice.authorizationStatus(for: type) {
            case .authorized:
                break
            case .notDetermined:
                group.enter()
                AVCaptureDevice.requestAccess(for: type) { allowed in
                    lock.lock(); granted = granted && allowed; lock.unlock()
                    group.leave()
                }
            default:
                lock.lock(); granted = false; lock.unlock()
            }
        }

        request(.video, needed: camera)
        request(.audio, needed: microphone)
        group.notify(queue: .main) { completion(granted) }
    }

    func start(configuration: RecordingConfiguration, outputURL: URL) throws {
        guard writer == nil else { return }
        // Although these CoreGraphics permission APIs were declared available
        // in the macOS 10.15 SDK, some Catalina releases do not export them.
        // Calling them on Catalina can crash at runtime. Let AVCaptureScreenInput
        // use Catalina's native Screen Recording permission flow instead.
        if #available(macOS 11.0, *) {
            if !CGPreflightScreenCaptureAccess() {
                CGRequestScreenCaptureAccess()
                throw RecorderError.screenPermissionDenied
            }
        }

        self.configuration = configuration
        self.outputURL = outputURL
        framesPerSecond = configuration.quality.fps
        timeline.reset()
        isStopping = false
        startedWriting = false

        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        let displayBounds = CGDisplayBounds(configuration.displayID)
        let nativeWidth = CGFloat(CGDisplayPixelsWide(configuration.displayID))
        let nativeHeight = CGFloat(CGDisplayPixelsHigh(configuration.displayID))
        guard nativeWidth > 0, nativeHeight > 0, displayBounds.width > 0, displayBounds.height > 0 else {
            throw RecorderError.displayUnavailable
        }
        let backing = nativeWidth / displayBounds.width
        let crop = configuration.cropRect.flatMap { rect -> CGRect? in
            guard rect.width >= 2, rect.height >= 2 else { return nil }
            return rect
        }
        let sourceWidth = (crop?.width ?? displayBounds.width) * backing
        let sourceHeight = (crop?.height ?? displayBounds.height) * backing
        let scale = min(1, min(CGFloat(configuration.quality.width) / sourceWidth,
                               CGFloat(configuration.quality.height) / sourceHeight))
        let width = max(2, Int(sourceWidth * scale) / 2 * 2)
        let height = max(2, Int(sourceHeight * scale) / 2 * 2)
        outputSize = CGSize(width: width, height: height)

        let assetWriter: AVAssetWriter
        do {
            assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw RecorderError.cannotCreateWriter(error.localizedDescription)
        }
        writer = assetWriter

        let compression: [String: Any] = [
            AVVideoAverageBitRateKey: configuration.quality.bitrate,
            AVVideoProfileLevelKey: AVVideoProfileLevelH264MainAutoLevel,
            AVVideoExpectedSourceFrameRateKey: configuration.quality.fps,
            AVVideoMaxKeyFrameIntervalKey: configuration.quality.fps * 2,
            AVVideoAllowFrameReorderingKey: false
        ]
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: compression
        ]
        let newVideoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        newVideoInput.expectsMediaDataInRealTime = true

        do {
            guard assetWriter.canAdd(newVideoInput) else { throw RecorderError.cannotCreateWriter("H.264 encoder is unavailable.") }
            assetWriter.add(newVideoInput)

            let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: newVideoInput,
                sourcePixelBufferAttributes: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                    kCVPixelBufferWidthKey as String: width,
                    kCVPixelBufferHeightKey as String: height,
                    kCVPixelBufferIOSurfacePropertiesKey as String: [:]
                ]
            )

            var newAudioInput: AVAssetWriterInput?
            if configuration.audioDevice != nil {
                let settings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 44_100,
                    AVNumberOfChannelsKey: 1,
                    AVEncoderBitRateKey: 64_000
                ]
                let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
                input.expectsMediaDataInRealTime = true
                guard assetWriter.canAdd(input) else { throw RecorderError.microphoneUnavailable }
                assetWriter.add(input)
                newAudioInput = input
            }

            videoInput = newVideoInput
            audioInput = newAudioInput
            pixelAdaptor = adaptor
            try configureScreenSession(configuration: configuration, scale: scale)
            try configureCameraSession(device: configuration.cameraDevice)
        } catch {
            writer?.cancelWriting()
            clearState()
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }

        screenSession.startRunning()
        cameraSession?.startRunning()
    }

    func stop() {
        guard writer != nil, !isStopping else { return }
        isStopping = true
        screenSession.stopRunning()
        cameraSession?.stopRunning()

        writerQueue.async { [weak self] in
            guard let self = self, let writer = self.writer else { return }
            guard self.startedWriting else {
                let url = self.outputURL
                writer.cancelWriting()
                self.clearState()
                if let url = url {
                    try? FileManager.default.removeItem(at: url)
                }
                let error = RecorderError.cannotCreateWriter("No video frames were captured.")
                DispatchQueue.main.async { self.delegate?.recorder(self, didFail: error) }
                return
            }
            self.videoInput?.markAsFinished()
            self.audioInput?.markAsFinished()
            writer.finishWriting { [weak self] in
                guard let self = self else { return }
                let url = self.outputURL
                let error = writer.error
                self.clearState()
                DispatchQueue.main.async {
                    if writer.status == .completed, let url = url {
                        self.delegate?.recorder(self, didFinish: url)
                    } else {
                        self.delegate?.recorder(self, didFail: error ?? RecorderError.cannotCreateWriter("The recording could not be finalized."))
                    }
                }
            }
        }
    }

    private func configureScreenSession(configuration: RecordingConfiguration, scale: CGFloat) throws {
        screenSession.beginConfiguration()
        defer { screenSession.commitConfiguration() }

        for input in screenSession.inputs { screenSession.removeInput(input) }
        for output in screenSession.outputs { screenSession.removeOutput(output) }

        guard let screenInput = AVCaptureScreenInput(displayID: configuration.displayID) else {
            throw RecorderError.cannotAddScreenInput
        }
        screenInput.minFrameDuration = CMTime(value: 1, timescale: CMTimeScale(configuration.quality.fps))
        screenInput.scaleFactor = scale
        // cropRect is stored in display points. The capture buffer is in pixels.
        if let crop = configuration.cropRect, crop.width >= 2, crop.height >= 2 {
            let bounds = CGDisplayBounds(configuration.displayID)
            let pixelsWide = CGFloat(CGDisplayPixelsWide(configuration.displayID))
            let pixelsHigh = CGFloat(CGDisplayPixelsHigh(configuration.displayID))
            let backing = bounds.width > 0 ? pixelsWide / bounds.width : 1
            let requested = CGRect(
                x: crop.origin.x * backing,
                y: crop.origin.y * backing,
                width: crop.width * backing,
                height: crop.height * backing
            )
            let visible = requested.intersection(CGRect(x: 0, y: 0, width: pixelsWide, height: pixelsHigh))
            if visible.width >= 2, visible.height >= 2 {
                screenInput.cropRect = visible
            }
        }
        screenInput.capturesCursor = configuration.capturesCursor
        screenInput.capturesMouseClicks = false
        guard screenSession.canAddInput(screenInput) else { throw RecorderError.cannotAddScreenInput }
        screenSession.addInput(screenInput)

        screenOutput.alwaysDiscardsLateVideoFrames = true
        screenOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        screenOutput.setSampleBufferDelegate(self, queue: writerQueue)
        guard screenSession.canAddOutput(screenOutput) else { throw RecorderError.cannotAddOutput }
        screenSession.addOutput(screenOutput)

        if let device = configuration.audioDevice {
            let deviceInput = try AVCaptureDeviceInput(device: device)
            guard screenSession.canAddInput(deviceInput) else { throw RecorderError.microphoneUnavailable }
            screenSession.addInput(deviceInput)
            audioOutput.setSampleBufferDelegate(self, queue: writerQueue)
            guard screenSession.canAddOutput(audioOutput) else { throw RecorderError.cannotAddOutput }
            screenSession.addOutput(audioOutput)
        }
    }

    private func configureCameraSession(device: AVCaptureDevice?) throws {
        latestCameraBuffer = nil
        guard let device = device else {
            cameraSession = nil
            return
        }

        let session = AVCaptureSession()
        session.beginConfiguration()
        session.sessionPreset = .low
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw RecorderError.cameraUnavailable }
        session.addInput(input)
        cameraOutput.alwaysDiscardsLateVideoFrames = true
        cameraOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        cameraOutput.setSampleBufferDelegate(self, queue: cameraQueue)
        guard session.canAddOutput(cameraOutput) else { throw RecorderError.cannotAddOutput }
        session.addOutput(cameraOutput)
        session.commitConfiguration()
        cameraSession = session
    }

    private func appendVideo(_ sampleBuffer: CMSampleBuffer) {
        guard !isStopping else { return }
        guard let source = CMSampleBufferGetImageBuffer(sampleBuffer),
              let writer = writer,
              let videoInput = videoInput,
              let adaptor = pixelAdaptor else { return }

        if !startedWriting {
            guard writer.startWriting() else {
                fail(writer.error ?? RecorderError.cannotCreateWriter("The writer did not start."))
                return
            }
            // File time always starts at zero. Capture clocks are rebased in RecordingTimeline.
            writer.startSession(atSourceTime: .zero)
            startedWriting = true
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.recorderDidStart(self)
            }
        }
        guard videoInput.isReadyForMoreMediaData else { return }

        let targetBuffer: CVPixelBuffer
        if configuration?.cameraDevice != nil,
           let pool = adaptor.pixelBufferPool,
           let composed = makeComposedBuffer(screen: source, pool: pool) {
            targetBuffer = composed
        } else if CVPixelBufferGetWidth(source) == Int(outputSize.width),
                  CVPixelBufferGetHeight(source) == Int(outputSize.height) {
            targetBuffer = source
        } else if let pool = adaptor.pixelBufferPool,
                  let scaled = makeScaledBuffer(screen: source, pool: pool) {
            targetBuffer = scaled
        } else {
            return
        }

        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(max(framesPerSecond, 1)))
        let time = timeline.videoTime(
            for: CMSampleBufferGetPresentationTimeStamp(sampleBuffer),
            frameDuration: frameDuration
        )
        adaptor.append(targetBuffer, withPresentationTime: time)
    }

    private func makeScaledBuffer(screen: CVPixelBuffer, pool: CVPixelBufferPool) -> CVPixelBuffer? {
        var result: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &result) == kCVReturnSuccess,
              let output = result else { return nil }
        let target = CGRect(origin: .zero, size: outputSize)
        let image = aspectFill(CIImage(cvPixelBuffer: screen), into: target)
        ciContext.render(image, to: output, bounds: target, colorSpace: CGColorSpaceCreateDeviceRGB())
        return output
    }

    private func makeComposedBuffer(screen: CVPixelBuffer, pool: CVPixelBufferPool) -> CVPixelBuffer? {
        var result: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &result) == kCVReturnSuccess,
              let output = result else { return nil }

        let target = CGRect(origin: .zero, size: outputSize)
        var image = aspectFill(CIImage(cvPixelBuffer: screen), into: target)

        cameraLock.lock()
        let camera = latestCameraBuffer
        cameraLock.unlock()

        if let camera = camera, let config = configuration {
            let margin = max(12, outputSize.width * 0.018)
            let cameraWidth = outputSize.width * config.cameraScale
            let cameraHeight = cameraWidth * 9 / 16
            let origin: CGPoint
            switch config.cameraPosition {
            case .topLeft:
                origin = CGPoint(x: margin, y: outputSize.height - cameraHeight - margin)
            case .topRight:
                origin = CGPoint(x: outputSize.width - cameraWidth - margin, y: outputSize.height - cameraHeight - margin)
            case .bottomLeft:
                origin = CGPoint(x: margin, y: margin)
            case .bottomRight:
                origin = CGPoint(x: outputSize.width - cameraWidth - margin, y: margin)
            }
            let rect = CGRect(origin: origin, size: CGSize(width: cameraWidth, height: cameraHeight))
            let cameraImage = aspectFill(CIImage(cvPixelBuffer: camera), into: rect)
            image = cameraImage.composited(over: image)
        }

        ciContext.render(image, to: output, bounds: target, colorSpace: CGColorSpaceCreateDeviceRGB())
        return output
    }

    private func aspectFill(_ image: CIImage, into rect: CGRect) -> CIImage {
        guard image.extent.width > 0, image.extent.height > 0 else { return image }
        let scale = max(rect.width / image.extent.width, rect.height / image.extent.height)
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let translated = scaled.transformed(by: CGAffineTransform(
            translationX: rect.midX - scaled.extent.midX,
            y: rect.midY - scaled.extent.midY
        ))
        return translated.cropped(to: rect)
    }

    private func appendAudio(_ sampleBuffer: CMSampleBuffer) {
        guard !isStopping, startedWriting, let input = audioInput, input.isReadyForMoreMediaData else { return }
        var duration = CMSampleBufferGetDuration(sampleBuffer)
        if !duration.isNumeric || duration.seconds <= 0 || duration.seconds > 0.5 {
            let samples = max(CMSampleBufferGetNumSamples(sampleBuffer), 1)
            var timescale: CMTimeScale = 44_100
            if let format = CMSampleBufferGetFormatDescription(sampleBuffer),
               let stream = CMAudioFormatDescriptionGetStreamBasicDescription(format),
               stream.pointee.mSampleRate > 0 {
                timescale = CMTimeScale(stream.pointee.mSampleRate.rounded())
            }
            duration = CMTime(value: CMTimeValue(samples), timescale: timescale)
        }
        let time = timeline.audioTime(
            for: CMSampleBufferGetPresentationTimeStamp(sampleBuffer),
            duration: duration
        )
        guard let retimed = retimedSampleBuffer(sampleBuffer, at: time, duration: duration) else { return }
        input.append(retimed)
    }

    private func retimedSampleBuffer(_ sampleBuffer: CMSampleBuffer, at time: CMTime, duration: CMTime) -> CMSampleBuffer? {
        var timing = CMSampleTimingInfo(duration: duration, presentationTimeStamp: time, decodeTimeStamp: .invalid)
        var copy: CMSampleBuffer?
        let status = CMSampleBufferCreateCopyWithNewTiming(
            allocator: nil,
            sampleBuffer: sampleBuffer,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleBufferOut: &copy
        )
        return status == noErr ? copy : nil
    }

    private func fail(_ error: Error) {
        // stopRunning waits for the sample callback to finish, so it must not
        // run on the capture queue or the session can deadlock.
        let camera = cameraSession
        let url = outputURL
        let removeFile = !startedWriting
        writer?.cancelWriting()
        clearState()
        if removeFile, let url = url {
            try? FileManager.default.removeItem(at: url)
        }
        DispatchQueue.main.async { [weak self] in
            self?.screenSession.stopRunning()
            camera?.stopRunning()
            guard let self = self else { return }
            self.delegate?.recorder(self, didFail: error)
        }
    }

    private func clearState() {
        cameraLock.lock(); latestCameraBuffer = nil; cameraLock.unlock()
        writer = nil
        videoInput = nil
        audioInput = nil
        pixelAdaptor = nil
        cameraSession = nil
        configuration = nil
        outputURL = nil
        startedWriting = false
        isStopping = false
        framesPerSecond = 15
        timeline.reset()
    }
}

/// Maps capture timestamps onto a file timeline that starts at zero.
///
/// Screen-capture buffers sometimes begin at time zero and then jump to the
/// host clock (hours since boot). Writing those values unchanged holds the
/// first frame for hours. A forward jump larger than `maxGap` is treated as a
/// broken clock and the file timeline stays continuous. Video and audio share
/// one epoch so a track that starts later stays aligned with the other.
private final class RecordingTimeline {
    private var epoch: CMTime?
    private var lastVideo = CMTime.invalid
    private var lastAudio = CMTime.invalid
    private let maxGap: Double = 30

    func reset() {
        epoch = nil
        lastVideo = .invalid
        lastAudio = .invalid
    }

    func videoTime(for source: CMTime, frameDuration: CMTime) -> CMTime {
        let result = map(source, step: frameDuration, last: lastVideo)
        epoch = result.epoch
        lastVideo = result.time
        return result.time
    }

    func audioTime(for source: CMTime, duration: CMTime) -> CMTime {
        let result = map(source, step: duration, last: lastAudio)
        epoch = result.epoch
        lastAudio = result.time
        return result.time
    }

    private func map(_ source: CMTime, step: CMTime, last: CMTime) -> (time: CMTime, epoch: CMTime?) {
        let advance = (step.isNumeric && step.seconds > 0) ? step : CMTime(value: 1, timescale: 600)
        let sourceIsUsable = source.isNumeric && source.seconds.isFinite
        var output: CMTime
        var rebase = false
        var nextEpoch = epoch

        if !sourceIsUsable {
            output = last.isNumeric ? CMTimeAdd(last, advance) : .zero
        } else if let epoch = epoch {
            output = CMTimeSubtract(source, epoch)
            let end = timelineEnd()
            if !output.isNumeric || output.seconds - end.seconds > maxGap {
                output = CMTimeAdd(end, advance)
                rebase = true
            } else if output.seconds < 0 {
                output = last.isNumeric ? CMTimeAdd(last, advance) : .zero
            }
        } else {
            output = .zero
            rebase = true
        }

        var scaled = CMTimeConvertScale(output, timescale: 600, method: .roundHalfAwayFromZero)
        if last.isNumeric && CMTimeCompare(scaled, last) <= 0 {
            let tick = CMTimeConvertScale(advance, timescale: 600, method: .roundHalfAwayFromZero)
            let stepTick = tick.isNumeric && tick.value > 0 ? tick : CMTime(value: 1, timescale: 600)
            scaled = CMTimeAdd(last, stepTick)
        }
        if rebase, sourceIsUsable {
            nextEpoch = CMTimeSubtract(source, scaled)
        }
        return (scaled, nextEpoch)
    }

    private func timelineEnd() -> CMTime {
        switch (lastVideo.isNumeric, lastAudio.isNumeric) {
        case (true, true):
            return CMTimeMaximum(lastVideo, lastAudio)
        case (true, false):
            return lastVideo
        case (false, true):
            return lastAudio
        default:
            return .zero
        }
    }
}

extension ScreenRecorder: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if output === screenOutput {
            appendVideo(sampleBuffer)
        } else if output === audioOutput {
            appendAudio(sampleBuffer)
        } else if output === cameraOutput, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            cameraLock.lock(); latestCameraBuffer = buffer; cameraLock.unlock()
        }
    }
}
