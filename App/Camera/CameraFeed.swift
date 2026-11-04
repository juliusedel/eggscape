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
        /// iOS has not asked for camera access yet, and a run waits for the camera: its calibration screen first says
        /// what the camera is for and then asks (`askForAccess(for:)`).
        case notAsked
        /// The iOS prompt for camera access is up.
        case asking
    }

    /// What iOS knows and asks about camera access; tests answer in its place.
    struct Access {
        var status: @MainActor () -> AVAuthorizationStatus
        var request: @MainActor () async -> Bool
        var hasRearCamera: @MainActor () -> Bool

        static var system: Access {
            Access(
                status: { AVCaptureDevice.authorizationStatus(for: .video) },
                request: { await AVCaptureDevice.requestAccess(for: .video) },
                hasRearCamera: { CaptureController.hasRearCamera }
            )
        }
    }

    private(set) var status = Status.idle
    @ObservationIgnored let controller = CaptureController()
    /// Called when the player answers the system's camera prompt with "no"; `AppServices` then switches the background
    /// to white, so the settings show what the player sees.
    @ObservationIgnored var onDeclined: () -> Void = {}
    /// The runs that show the camera; on "Nochmal" the new one starts before the old one stops.
    @ObservationIgnored private var owners = Leases()
    @ObservationIgnored private let access: Access

    init(access: Access = .system) {
        self.access = access
    }

    /// `true` if the camera can be shown right now or after `start(for:)`.
    var isUsable: Bool {
        status != .unavailable && status != .denied
    }

    /// The player said "no" earlier, or camera access is restricted on this device: iOS will not ask again, so only
    /// the iOS settings can allow it.
    var isDeniedBySystem: Bool {
        [.denied, .restricted].contains(access.status())
    }

    /// Asks for camera access if needed; returns whether the camera may be used.
    func requestAccess() async -> Bool {
        let granted: Bool
        switch access.status() {
        case .authorized:
            granted = true
        case .notDetermined:
            status = .asking
            granted = await access.request()
            if !granted {
                onDeclined()
            }
        default:
            granted = false
        }
        if !granted {
            status = .denied
        } else if [.denied, .notAsked, .asking].contains(status) {
            // Allowed in the prompt, or in the iOS settings after an earlier "no".
            status = .idle
        }
        return granted
    }

    /// Shows the camera for `owner` until the last owner has called `stop(for:)`. If the player has never been asked
    /// for access (a fresh install, where the camera is the default, or after resetting the privacy settings), it
    /// waits as `.notAsked` for `askForAccess(for:)`, so the prompt comes once the player can tell what it is for.
    /// Without a rear camera, as in the Simulator, it does not wait at all: there is nothing to allow.
    func start(for owner: AnyObject) {
        owners.acquire(owner)
        switch access.status() {
        case .authorized:
            startSession()
        case .notDetermined:
            if !access.hasRearCamera() {
                status = .unavailable
            } else if status != .asking {
                status = .notAsked
            }
        default:
            status = .denied
        }
    }

    /// Brings up the iOS prompt for camera access, then shows the camera for `owner` if the player allowed it. While
    /// the prompt is up, a second call (a quick second tap) changes nothing.
    func askForAccess(for owner: AnyObject) {
        owners.acquire(owner)
        guard status != .asking else { return }
        status = .asking
        Task {
            if await requestAccess(), owners.isHeld {
                startSession()
            }
        }
    }

    func stop(for owner: AnyObject) {
        guard owners.release(owner) else { return }
        controller.stop()
        // A run that waited for the question is gone; the next one waits again.
        if status == .running || status == .notAsked {
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
