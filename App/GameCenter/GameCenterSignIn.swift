import Foundation

/// When Apple's Game Center sign-in sheet is shown. GameKit signs the player in silently at launch; a sheet it asks
/// for there is kept until a screen that needs Game Center opens, instead of popping up over a run. A plain value, so
/// `GameCenterService` only carries out the returned steps and the rules are testable without GameKit.
struct GameCenterSignIn<Sheet> {
    enum Step {
        case nothing
        /// Assign GameKit's authenticate handler, which starts authenticating (again).
        case authenticate
        case present(Sheet)
        /// The player has just signed in.
        case didSignIn
    }

    private(set) var status = GameCenterService.Status.signedOut
    /// GameKit's sign-in sheet, until a screen asks for it.
    private var sheet: Sheet?
    /// Open screens that wait for the sign-in: GameKit's next sheet is shown right away instead of being kept, so they
    /// never wait for an answer that does not come. A screen that closed no longer waits, so a late sheet does not pop
    /// up over whatever is on screen by then, such as a run.
    private var waitingScreens = Leases()

    /// Signs in without showing anything, once at launch.
    mutating func authenticateAtLaunch() -> Step {
        guard status == .signedOut, sheet == nil else { return .nothing }
        status = .signingIn
        return .authenticate
    }

    /// `screen`, which needs Game Center, appeared, or the player tapped "Erneut versuchen" on it.
    mutating func signIn(for screen: AnyObject) -> Step {
        switch status {
        case .signedIn:
            return .nothing
        case .signingIn:
            waitingScreens.acquire(screen)
            return .nothing
        case .signedOut, .unavailable:
            status = .signingIn
            if let sheet {
                self.sheet = nil
                return .present(sheet)
            }
            waitingScreens.acquire(screen)
            return .authenticate
        }
    }

    /// `screen` closed: a sheet GameKit asks for from now on is kept for the next screen that needs Game Center.
    mutating func stopWaitingForSignIn(for screen: AnyObject) {
        waitingScreens.release(screen)
    }

    /// GameKit asks the player to sign in with `newSheet`.
    mutating func needsSignIn(_ newSheet: Sheet) -> Step {
        if waitingScreens.isHeld {
            waitingScreens = Leases()
            return .present(newSheet)
        }
        sheet = newSheet
        switch status {
        case .signingIn:
            // Nobody is waiting for it, e.g. at launch, or the screen that asked has closed since.
            status = .signedOut
        case .signedIn:
            // Signed out in the meantime (GameKit checks again whenever the app returns to the foreground). A screen
            // that is open offers to try again, which shows the sheet.
            status = .unavailable(String(localized: "Du bist nicht mehr bei Game Center angemeldet."))
        case .signedOut, .unavailable:
            break
        }
        return .nothing
    }

    /// GameKit reports the player as signed in, also again whenever the app returns to the foreground.
    mutating func signedIn(name: String) -> Step {
        let step: Step = if case .signedIn = status {
            .nothing
        } else {
            .didSignIn
        }
        sheet = nil
        waitingScreens = Leases()
        status = .signedIn(name: name)
        return step
    }

    /// GameKit reports an error, or a player who is neither signed in nor offered a sheet.
    mutating func failed(_ message: String?) {
        sheet = nil
        waitingScreens = Leases()
        status = .unavailable(message ?? String(localized: "Game Center ist nicht verfügbar."))
    }
}

extension GameCenterSignIn.Step: Equatable where Sheet: Equatable {}
