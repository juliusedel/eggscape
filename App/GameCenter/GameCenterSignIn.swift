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
    /// A screen is waiting for the sign-in: GameKit's next sheet is shown right away instead of being kept, so the
    /// screen never waits for an answer that does not come.
    private var presentsNextSheet = false

    /// Signs in without showing anything, once at launch.
    mutating func authenticateAtLaunch() -> Step {
        guard status == .signedOut, sheet == nil else { return .nothing }
        status = .signingIn
        return .authenticate
    }

    /// A screen that needs Game Center appeared, or the player tapped "Erneut versuchen".
    mutating func signIn() -> Step {
        switch status {
        case .signedIn:
            return .nothing
        case .signingIn:
            presentsNextSheet = true
            return .nothing
        case .signedOut, .unavailable:
            status = .signingIn
            if let sheet {
                self.sheet = nil
                return .present(sheet)
            }
            presentsNextSheet = true
            return .authenticate
        }
    }

    /// GameKit asks the player to sign in with `newSheet`.
    mutating func needsSignIn(_ newSheet: Sheet) -> Step {
        if presentsNextSheet {
            presentsNextSheet = false
            return .present(newSheet)
        }
        sheet = newSheet
        switch status {
        case .signingIn:
            // Nobody is waiting for it, e.g. at launch.
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
        presentsNextSheet = false
        status = .signedIn(name: name)
        return step
    }

    /// GameKit reports an error, or a player who is neither signed in nor offered a sheet.
    mutating func failed(_ message: String?) {
        sheet = nil
        presentsNextSheet = false
        status = .unavailable(message ?? String(localized: "Game Center ist nicht verfügbar."))
    }
}

extension GameCenterSignIn.Step: Equatable where Sheet: Equatable {}
