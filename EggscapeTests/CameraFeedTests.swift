import AVFoundation
@testable import Eggscape
import Testing

/// The camera question of a fresh install, where the camera is the default background: a run waits with it until its
/// calibration screen has said what the camera is for, and "Weiter" brings up exactly one prompt. The Simulator has no
/// camera and iOS cannot be answered from a test, so a fake plays iOS.
@MainActor
struct CameraFeedTests {
    /// Stands in for iOS: it knows the authorization status and keeps a prompt open until the test answers it.
    @MainActor
    private final class FakeSystem {
        var status = AVAuthorizationStatus.notDetermined
        var hasRearCamera = true
        private(set) var prompts = 0
        private var pendingAnswer: CheckedContinuation<Bool, Never>?

        var isPromptUp: Bool {
            pendingAnswer != nil
        }

        var access: CameraFeed.Access {
            CameraFeed.Access(
                status: { self.status },
                request: {
                    self.prompts += 1
                    return await withCheckedContinuation { self.pendingAnswer = $0 }
                },
                hasRearCamera: { self.hasRearCamera }
            )
        }

        /// The player taps "Erlauben" or "Nicht erlauben".
        func answer(allowing: Bool) {
            status = allowing ? .authorized : .denied
            pendingAnswer?.resume(returning: allowing)
            pendingAnswer = nil
        }
    }

    /// Lets the feed's tasks run until `condition` holds, or gives up after a while.
    private func settle(until condition: () -> Bool) async {
        for _ in 0 ..< 200 where !condition() {
            await Task.yield()
        }
    }

    @Test func aRunWaitsForItsCalibrationScreenToAsk() {
        let system = FakeSystem()
        let feed = CameraFeed(access: system.access)
        let run = LeaseOwner()

        feed.start(for: run)

        #expect(feed.status == .notAsked)
        #expect(feed.isUsable, "the camera may still come")
        #expect(system.prompts == 0)
    }

    @Test func withoutARearCameraThereIsNothingToAsk() {
        let system = FakeSystem()
        system.hasRearCamera = false
        let feed = CameraFeed(access: system.access)

        feed.start(for: LeaseOwner())

        #expect(feed.status == .unavailable)
        #expect(system.prompts == 0)
    }

    @Test(arguments: [AVAuthorizationStatus.denied, .restricted])
    func iOSDoesNotAskAgain(after status: AVAuthorizationStatus) {
        let system = FakeSystem()
        system.status = status
        let feed = CameraFeed(access: system.access)

        feed.start(for: LeaseOwner())

        #expect(feed.status == .denied)
        #expect(feed.isDeniedBySystem)
        #expect(system.prompts == 0)
    }

    @Test func aQuickSecondTapBringsUpNoSecondPrompt() async {
        let system = FakeSystem()
        let feed = CameraFeed(access: system.access)
        var declines = 0
        feed.onDeclined = { declines += 1 }
        let run = LeaseOwner()
        feed.start(for: run)

        feed.askForAccess(for: run)
        feed.askForAccess(for: run)
        await settle { system.isPromptUp }

        #expect(feed.status == .asking)
        feed.askForAccess(for: run)
        await settle { system.prompts > 1 }
        #expect(system.prompts == 1)

        // "Nicht erlauben": the run goes on without the camera, and `AppServices` switches the background to Weiß.
        system.answer(allowing: false)
        await settle { feed.status != .asking }
        #expect(feed.status == .denied)
        #expect(!feed.isUsable)
        #expect(declines == 1)
    }

    @Test func allowingEndsTheQuestion() async {
        let system = FakeSystem()
        let feed = CameraFeed(access: system.access)
        var declines = 0
        feed.onDeclined = { declines += 1 }
        let run = LeaseOwner()
        feed.start(for: run)

        feed.askForAccess(for: run)
        await settle { system.isPromptUp }
        system.answer(allowing: true)
        await settle { feed.status != .asking }

        // Then the camera starts, which the Simulator does not have; either way the question is over.
        #expect(![.notAsked, .asking, .denied].contains(feed.status))
        #expect(!feed.isDeniedBySystem)
        #expect(declines == 0)
        #expect(system.prompts == 1)
        feed.stop(for: run)
    }

    @Test func aRunThatLeavesTakesItsQuestionAlong() {
        let system = FakeSystem()
        let feed = CameraFeed(access: system.access)
        let run = LeaseOwner()
        feed.start(for: run)

        feed.stop(for: run)

        #expect(feed.status == .idle)
        #expect(system.prompts == 0)
    }

    /// Einstellungen → Hintergrund → Kamera asks iOS directly.
    @Test func theSettingsGetTheAnswer() async {
        let system = FakeSystem()
        let feed = CameraFeed(access: system.access)

        async let answer = feed.requestAccess()
        await settle { system.isPromptUp }
        #expect(feed.status == .asking)
        system.answer(allowing: true)

        #expect(await answer)
        #expect(feed.status == .idle)
    }
}
