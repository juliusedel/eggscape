@testable import Eggscape
import Testing
import UIKit

struct LeasesTests {
    @Test func heldUntilTheLastOwnerLeaves() {
        let oldRun = LeaseOwner()
        let newRun = LeaseOwner()
        var leases = Leases()
        leases.acquire(oldRun)
        // "Nochmal": the new run starts before the old one stops.
        leases.acquire(newRun)
        let stopsWithOld = leases.release(oldRun)
        #expect(!stopsWithOld)
        #expect(leases.isHeld)
        let stopsWithNew = leases.release(newRun)
        #expect(stopsWithNew)
        #expect(!leases.isHeld)
    }

    @Test func releasingTwiceChangesNothing() {
        let owner = LeaseOwner()
        var leases = Leases()
        leases.acquire(owner)
        let first = leases.release(owner)
        let second = leases.release(owner)
        #expect(first)
        #expect(!second)
        #expect(!leases.isHeld)
    }

    @Test func acquiringTwiceNeedsOneRelease() {
        let owner = LeaseOwner()
        var leases = Leases()
        leases.acquire(owner)
        leases.acquire(owner)
        let stops = leases.release(owner)
        #expect(stops)
        #expect(!leases.isHeld)
    }

    @Test func othersCannotEndALease() {
        let owner = LeaseOwner()
        var leases = Leases()
        leases.acquire(owner)
        let stops = leases.release(LeaseOwner())
        #expect(!stops)
        #expect(leases.isHeld)
        #expect(!Leases().isHeld)
    }

    @Test func ownersThatWentAwayDoNotKeepTheServiceOn() {
        var leases = Leases()
        do {
            let forgetful = LeaseOwner()
            leases.acquire(forgetful)
        }
        #expect(!leases.isHeld)
        // It never let go, so the service is still on until anybody else releases.
        let stops = leases.release(LeaseOwner())
        #expect(stops)
    }
}

@MainActor
struct IdleTimerTests {
    @Test func screenStaysAwakeWhileAnyRunNeedsIt() {
        let oldRun = LeaseOwner()
        let newRun = LeaseOwner()
        IdleTimer.setDisabled(true, for: oldRun)
        IdleTimer.setDisabled(true, for: newRun)
        IdleTimer.setDisabled(false, for: oldRun)
        #expect(UIApplication.shared.isIdleTimerDisabled)
        IdleTimer.setDisabled(false, for: oldRun)
        #expect(UIApplication.shared.isIdleTimerDisabled)
        IdleTimer.setDisabled(false, for: newRun)
        #expect(!UIApplication.shared.isIdleTimerDisabled)
    }
}
