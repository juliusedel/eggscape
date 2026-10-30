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
    /// Called when the player answers the system's camera prompt with "no"; `AppServices` then switches the background
    /// to white, so the settings show what the player sees and choosing "Kamera" there explains how to allow it.
    @ObservationIgnored var onDeclined: () -> Void = {}
    /// The runs that show the camera; on "Nochmal" the new one starts before the old one stops.
    @ObservationIgnored private var owners = Leases()

    /// `true` if the camera can be shown right now or after `start(for:)`.
    var isUsable: Bool {
        status != .unavailable && status != .denied
    }

    /// Asks for camera access if needed; returns whether the camera may be used.
    func requestAccess() async -> Bool {
        let granted: Bool
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            granted = true
        case .notDetermined:
            granted = await AVCaptureDevice.requestAccess(for: .video)
            if !granted {
                onDeclined()
            }
        default:
            granted = false
        }
        if !granted {
            status = .denied
        } else if status == .denied {
            // Allowed in the iOS settings after an earlier "no".
            status = .idle
        }
        return granted
    }

    /// Shows the camera for `owner` until the last owner has called `stop(for:)`. If the player has never been asked
    /// for access (a fresh install, where the camera is the default, or after resetting the privacy settings), it asks
    /// first when `mayAskForAccess` is set, and otherwise leaves the question to a later start. Without a rear camera,
    /// as in the Simulator, it does not ask at all: there is nothing to allow.
    func start(for owner: AnyObject, mayAskForAccess: Bool = true) {
        owners.acquire(owner)
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startSession()
        case .notDetermined:
            guard CaptureController.hasRearCamera else {
                status = .unavailable
                return
            }
            guard mayAskForAccess else { return }
            Task {
                if await requestAccess(), owners.isHeld {
                    startSession()
                }
            }
        default:
            status = .denied
        }
    }

    func stop(for owner: AnyObject) {
        guard owners.release(owner) else { return }
        controller.stop()
        if status == .running {
            status = .idle
        }
    }

    private func startSession() {
        let controller = controller
        Task {
            let running = await controller.start()
            // Everybody stopped while the session was starting up.
            guard owners.isHeld else {
                controller.stop()
                return
            }
            status = running ? .running : .unavailable
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

    /// Finding the camera needs no permission, so this can be checked before asking for it.
    static var hasRearCamera: Bool {
        rearCamera != nil
    }

    private static var rearCamera: AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
    }

    private func configure() -> Bool {
        guard let device = Self.rearCamera,
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
