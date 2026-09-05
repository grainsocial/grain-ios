import AVFoundation
import UIKit

/// Owns the AVFoundation capture graph behind the story camera. Every touch of
/// the session happens on `queue`, which is what makes the class safe to hand
/// across isolation boundaries despite AVFoundation's non-Sendable types.
final class StoryCameraSession: @unchecked Sendable {
    enum Failure: Error {
        case noCamera
        case captureFailed
    }

    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "social.grain.story-camera")
    private let photoOutput = AVCapturePhotoOutput()
    private var videoInput: AVCaptureDeviceInput?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    /// Tracks device orientation so the preview stays upright and photos
    /// come out the way the phone was held, without the UI having to rotate.
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var previewRotationObservation: NSKeyValueObservation?
    /// Capture delegates are only weakly held by AVFoundation; keep each one
    /// alive until its photo comes back.
    private var inFlight: [Int64: PhotoCaptureDelegate] = [:]

    static func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            true
        case .notDetermined:
            await AVCaptureDevice.requestAccess(for: .video)
        default:
            false
        }
    }

    /// Points the session at the camera on `position`, swapping out any
    /// previous input. Returns whether that camera has a flash.
    func configure(position: AVCaptureDevice.Position) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    try continuation.resume(returning: self.configureOnQueue(position: position))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func configureOnQueue(position: AVCaptureDevice.Position) throws -> Bool {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo

        if let videoInput {
            session.removeInput(videoInput)
            self.videoInput = nil
        }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
            ?? AVCaptureDevice.default(for: .video)
        else { throw Failure.noCamera }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw Failure.noCamera }
        session.addInput(input)
        videoInput = input

        if !session.outputs.contains(photoOutput) {
            guard session.canAddOutput(photoOutput) else { throw Failure.noCamera }
            session.addOutput(photoOutput)
        }
        photoOutput.maxPhotoQualityPrioritization = .balanced

        // Mirror the selfie camera so the photo matches what the preview showed.
        if let connection = photoOutput.connection(with: .video) {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = device.position == .front
        }
        rebuildRotationCoordinator(for: device)
        return device.hasFlash
    }

    /// Hooks the viewfinder layer up to the session and to orientation tracking.
    func attach(previewLayer: AVCaptureVideoPreviewLayer) {
        previewLayer.session = session
        queue.async {
            self.previewLayer = previewLayer
            if let device = self.videoInput?.device {
                self.rebuildRotationCoordinator(for: device)
            }
        }
    }

    /// Called on `queue`. Rebuilt whenever the device or preview layer changes.
    private func rebuildRotationCoordinator(for device: AVCaptureDevice) {
        let layer = previewLayer
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: layer)
        previewRotationObservation = coordinator.observe(
            \.videoRotationAngleForHorizonLevelPreview, options: [.initial, .new]
        ) { coordinator, _ in
            let angle = coordinator.videoRotationAngleForHorizonLevelPreview
            guard let connection = layer?.connection,
                  connection.isVideoRotationAngleSupported(angle)
            else { return }
            connection.videoRotationAngle = angle
        }
        rotationCoordinator = coordinator
    }

    func start() {
        queue.async {
            guard !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    func stop() {
        queue.async {
            guard self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    func capture(flash: AVCaptureDevice.FlashMode) async throws -> UIImage {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                let settings = AVCapturePhotoSettings()
                if self.photoOutput.supportedFlashModes.contains(flash) {
                    settings.flashMode = flash
                }
                if let connection = self.photoOutput.connection(with: .video),
                   let angle = self.rotationCoordinator?.videoRotationAngleForHorizonLevelCapture,
                   connection.isVideoRotationAngleSupported(angle)
                {
                    connection.videoRotationAngle = angle
                }
                let id = settings.uniqueID
                let delegate = PhotoCaptureDelegate { [weak self] result in
                    self?.queue.async { self?.inFlight[id] = nil }
                    continuation.resume(with: result)
                }
                self.inFlight[id] = delegate
                self.photoOutput.capturePhoto(with: settings, delegate: delegate)
            }
        }
    }
}

private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let completion: @Sendable (Result<UIImage, Error>) -> Void

    init(completion: @escaping @Sendable (Result<UIImage, Error>) -> Void) {
        self.completion = completion
    }

    func photoOutput(_: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error {
            completion(.failure(error))
        } else if let data = photo.fileDataRepresentation(), let image = UIImage(data: data) {
            completion(.success(image))
        } else {
            completion(.failure(StoryCameraSession.Failure.captureFailed))
        }
    }
}

/// UI-facing state for the story camera: permission, which lens is up, flash,
/// and whether a shot is in progress. Drives `StoryCameraSession` underneath.
@Observable
@MainActor
final class StoryCamera {
    enum Status: Equatable {
        case starting
        case ready
        case unauthorized
        case unavailable
    }

    private(set) var status: Status = .starting
    private(set) var position: AVCaptureDevice.Position = .back
    private(set) var hasFlash = false
    private(set) var isCapturing = false
    var flashMode: AVCaptureDevice.FlashMode = .off

    let session = StoryCameraSession()
    private let requestAccess: @Sendable () async -> Bool

    /// `requestAccess` defaults to the real permission prompt. A test passes
    /// its own answer so it can reach the denied branch without a dialog.
    init(requestAccess: @escaping @Sendable () async -> Bool = StoryCameraSession.requestAccess) {
        self.requestAccess = requestAccess
    }

    func start() async {
        guard await requestAccess() else {
            status = .unauthorized
            return
        }
        do {
            hasFlash = try await session.configure(position: position)
            session.start()
            status = .ready
        } catch {
            status = .unavailable
        }
    }

    func stop() {
        session.stop()
    }

    func flip() async {
        let next: AVCaptureDevice.Position = position == .back ? .front : .back
        guard let flash = try? await session.configure(position: next) else { return }
        position = next
        hasFlash = flash
    }

    func toggleFlash() {
        flashMode = flashMode == .off ? .on : .off
    }

    func capture() async -> UIImage? {
        guard status == .ready, !isCapturing else { return nil }
        isCapturing = true
        defer { isCapturing = false }
        return try? await session.capture(flash: hasFlash ? flashMode : .off)
    }
}
