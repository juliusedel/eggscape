import CoreMotion
import EggscapeCore
import os

/// Reads the sensor-fused gravity vector at 100 Hz on a dedicated queue and keeps the latest filtered tilt for the
/// game loop. Device motion needs no permission prompt.
@MainActor
final class MotionInput {
    private let manager = CMMotionManager()
    private let queue: OperationQueue
    private let store: TiltStore
    /// Runs, the nearby lobby and the calibration sheet; their screens may overlap.
    private var owners = Leases()

    init(filterTimeConstant: Double = GameConfig.standard.tiltFilterTimeConstant) {
        queue = OperationQueue()
        queue.name = "de.juliusedel.eggscape.motion"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInteractive
        store = TiltStore(filterTimeConstant: filterTimeConstant)
    }

    /// `false` in the Simulator and on devices without a gyroscope; the game then falls back to touch steering.
    var isAvailable: Bool {
        manager.isDeviceMotionAvailable
    }

    /// Latest low-pass filtered tilt in radians, `nil` before the first sample.
    var tilt: SIMD2<Double>? {
        store.tilt
    }

    /// Starts the updates for `owner`; they keep running until the last owner has called `stop(for:)`.
    func start(for owner: AnyObject) {
        owners.acquire(owner)
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 100
        let store = store
        // `@Sendable` keeps the handler off the main actor: it runs on `queue`.
        manager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: queue) { @Sendable motion, _ in
            guard let motion else { return }
            let gravity = SIMD3(motion.gravity.x, motion.gravity.y, motion.gravity.z)
            store.add(gravity: gravity, timestamp: motion.timestamp)
        }
    }

    /// Stops the updates and forgets the tilt once nobody needs them any more.
    func stop(for owner: AnyObject) {
        guard owners.release(owner) else { return }
        manager.stopDeviceMotionUpdates()
        store.reset()
    }
}

/// Hands the filtered tilt from the motion queue to the main thread.
final class TiltStore: Sendable {
    private struct State {
        var filter: GravityLowPass
        var tilt: SIMD2<Double>?
    }

    private let state: OSAllocatedUnfairLock<State>
    private let filterTimeConstant: Double

    init(filterTimeConstant: Double) {
        self.filterTimeConstant = filterTimeConstant
        state = OSAllocatedUnfairLock(initialState: State(filter: GravityLowPass(timeConstant: filterTimeConstant)))
    }

    var tilt: SIMD2<Double>? {
        state.withLock { $0.tilt }
    }

    func add(gravity: SIMD3<Double>, timestamp: Double) {
        state.withLock { state in
            let smoothed = state.filter.add(gravity, at: timestamp)
            state.tilt = TiltMath.tilt(gravity: smoothed)
        }
    }

    func reset() {
        let filter = GravityLowPass(timeConstant: filterTimeConstant)
        state.withLock { $0 = State(filter: filter) }
    }
}
