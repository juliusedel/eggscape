@testable import Eggscape
import Testing

/// Signing in is silent at launch, Apple's sheet appears only for a screen that needs Game Center, and no screen waits
/// for an answer that never comes. Strings stand in for GameKit's sign-in sheets.
struct GameCenterSignInTests {
    private func isUnavailable(_ status: GameCenterService.Status) -> Bool {
        if case .unavailable = status {
            true
        } else {
            false
        }
    }

    @Test func signsInSilentlyAtLaunch() {
        var signIn = GameCenterSignIn<String>()
        #expect(signIn.authenticateAtLaunch() == .authenticate)
        #expect(signIn.status == .signingIn)
        #expect(signIn.signedIn(name: "Mia") == .didSignIn)
        #expect(signIn.status == .signedIn(name: "Mia"))
        // GameKit reports the player again whenever the app returns to the foreground.
        #expect(signIn.signedIn(name: "Mia") == .nothing)
        #expect(signIn.signIn() == .nothing)
    }

    @Test func authenticatesOnceAtLaunch() {
        var signIn = GameCenterSignIn<String>()
        #expect(signIn.authenticateAtLaunch() == .authenticate)
        #expect(signIn.authenticateAtLaunch() == .nothing)
    }

    @Test func keepsTheLaunchSheetUntilAScreenAsks() {
        var signIn = GameCenterSignIn<String>()
        _ = signIn.authenticateAtLaunch()
        #expect(signIn.needsSignIn("sheet") == .nothing)
        #expect(signIn.status == .signedOut)
        #expect(signIn.signIn() == .present("sheet"))
        #expect(signIn.status == .signingIn)
        #expect(signIn.signedIn(name: "Mia") == .didSignIn)
    }

    @Test func aNewerSheetReplacesTheKeptOne() {
        var signIn = GameCenterSignIn<String>()
        _ = signIn.authenticateAtLaunch()
        _ = signIn.needsSignIn("first")
        #expect(signIn.needsSignIn("second") == .nothing)
        #expect(signIn.signIn() == .present("second"))
    }

    @Test func aScreenOpenedWhileGameKitIsBusyGetsTheSheet() {
        var signIn = GameCenterSignIn<String>()
        _ = signIn.authenticateAtLaunch()
        #expect(signIn.signIn() == .nothing)
        #expect(signIn.needsSignIn("sheet") == .present("sheet"))
        #expect(signIn.status == .signingIn)
    }

    @Test func aScreenStartsAuthenticationWhenNothingIsKnown() {
        var signIn = GameCenterSignIn<String>()
        #expect(signIn.signIn() == .authenticate)
        #expect(signIn.status == .signingIn)
        #expect(signIn.needsSignIn("sheet") == .present("sheet"))
    }

    @Test func aFailureOffersToTryAgain() {
        var signIn = GameCenterSignIn<String>()
        _ = signIn.authenticateAtLaunch()
        signIn.failed("Keine Verbindung")
        #expect(signIn.status == .unavailable("Keine Verbindung"))
        #expect(signIn.signIn() == .authenticate)
        #expect(signIn.status == .signingIn)
        signIn.failed(nil)
        #expect(isUnavailable(signIn.status))
    }

    @Test func aFailureDropsTheKeptSheet() {
        var signIn = GameCenterSignIn<String>()
        _ = signIn.authenticateAtLaunch()
        _ = signIn.needsSignIn("sheet")
        signIn.failed(nil)
        #expect(signIn.signIn() == .authenticate)
    }

    @Test func signingOutElsewhereOffersToSignInAgain() {
        var signIn = GameCenterSignIn<String>()
        _ = signIn.authenticateAtLaunch()
        _ = signIn.signedIn(name: "Mia")
        // Signed out in the iOS settings: GameKit asks again when the app returns to the foreground.
        #expect(signIn.needsSignIn("sheet") == .nothing)
        #expect(isUnavailable(signIn.status))
        #expect(signIn.signIn() == .present("sheet"))
        #expect(signIn.signedIn(name: "Mia") == .didSignIn)
    }
}
