/// The objects that currently need a shared device service, such as the motion sensors or the haptic engine.
///
/// Screens hand over in any order: on "Nochmal" the new run appears before the old one disappears. A service is
/// therefore on while anybody holds a lease and goes off only when the last owner leaves; acquiring or releasing
/// twice for the same owner changes nothing. Owners are held weakly, so one that goes away without releasing cannot
/// keep a service running for good.
struct Leases {
    private struct Lease {
        weak var owner: AnyObject?
    }

    private var leases: [ObjectIdentifier: Lease] = [:]

    /// `true` while anybody who is still around needs the service.
    var isHeld: Bool {
        leases.values.contains { $0.owner != nil }
    }

    mutating func acquire(_ owner: AnyObject) {
        leases[ObjectIdentifier(owner)] = Lease(owner: owner)
    }

    /// Returns `true` if the service was on and nobody needs it any more, so it has to stop now.
    @discardableResult
    mutating func release(_ owner: AnyObject) -> Bool {
        // Owners that went away without releasing still count here: the service is on because of them.
        let wasOn = !leases.isEmpty
        leases[ObjectIdentifier(owner)] = nil
        leases = leases.filter { $0.value.owner != nil }
        return wasOn && leases.isEmpty
    }
}

/// Holds a lease for a screen that has no object of its own, kept in the view's `@State`.
final class LeaseOwner {}
