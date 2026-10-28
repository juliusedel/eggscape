import AVFoundation
import Observation

/// The rear camera shown behind the spoon in camera mode. Frames are only displayed: nothing is recorded, stored or
/// sent anywhere.
@MainActor
@Observable
final class CameraFeed {
    enum Status: Equatable {
        case idle
        case running
        /// No rear camera (Simulator) or it could not be configured.
        case unavailable
        /// The player declined camera access.
        case denied
    }

    private(set) var status = Status.idle
    @ObservationIgnored let controller = CaptureController()

    /// `true` if the camera can be shown right now or after `start()`.
    var isUsable: Bool {
        status != .unavailable && status != .denied
    }

    /// Asks for camera access if needed; returns whether the camera may be used.
    func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if !granted {
                status = .denied
            }
            return granted
        default:
            status = .denied
            return false
        }
    }

    func start() {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            status = .denied
            return
        }
        let controller = controller
        Task {
            let running = await controller.start()
            status = running ? .running : .unavailable
        }
    }

    func stop() {
        controller.stop()
        if status == .running {
            status = .idle
        }
    }
}

/// Owns the capture session. Every access to `session` and `isConfigured` happens on `queue`, which is what makes
/// sharing this object between threads safe.
final class CaptureController: @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "de.juliusedel.eggscape.camera")
    private var isConfigured = false

    /// Configures the session on first use and starts it; returns whether it runs.
    func start() async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                if !isConfigured {
                    isConfigured = configure()
                }
                if isConfigured, !session.isRunning {
                    session.startRunning()
                }
                continuation.resume(returning: isConfigured && session.isRunning)
            }
        }
    }

    func stop() {
        queue.async { [self] in
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    private func configure() -> Bool {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device)
        else { return false }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .high
        guard session.canAddInput(input) else { return false }
        session.addInput(input)
        return true
    }
}
