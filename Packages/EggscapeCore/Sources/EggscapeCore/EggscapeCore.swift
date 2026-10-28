/// UI-free game logic shared by the app and its tests: physics, weather, seeded randomness and the
/// multiplayer wire format. Nothing in this module may import UIKit, SpriteKit or SwiftUI.
public enum EggscapeCore {
    /// Bumped whenever the multiplayer wire format changes; peers with different versions cannot race together.
    public static let protocolVersion = 1
}
