/// UI-free game logic shared by the app and its tests: physics, weather, seeded randomness and the
/// multiplayer wire format. Nothing in this module may import UIKit, SpriteKit or SwiftUI.
public enum EggscapeCore {
    /// Bumped whenever the multiplayer wire format or the shared physics (`GameConfig`) changes; peers with different
    /// versions cannot race together. 2: the smaller tipping point and the gentler wind and lightning.
    public static let protocolVersion = 2
}
