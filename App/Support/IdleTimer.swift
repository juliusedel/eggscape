import UIKit

/// `UIApplication.isIdleTimerDisabled` shared by all runs: on "Nochmal" the new run starts before the old one stops,
/// so the old one must not let the screen dim under the new one.
@MainActor
enum IdleTimer {
    private static var awakeOwners = Leases()

    /// Keeps the screen awake while any owner asks for it; asking twice or letting go twice changes nothing.
    static func setDisabled(_ disabled: Bool, for owner: AnyObject) {
        if disabled {
            awakeOwners.acquire(owner)
        } else {
            awakeOwners.release(owner)
        }
        UIApplication.shared.isIdleTimerDisabled = awakeOwners.isHeld
    }
}
