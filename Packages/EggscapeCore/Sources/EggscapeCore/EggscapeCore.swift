/// UI-free game logic shared by the app and its tests: physics, weather, seeded randomness and the
/// multiplayer wire format. Nothing in this module may import UIKit, SpriteKit or SwiftUI.
public enum EggscapeCore {
    /// Bumped whenever the multiplayer wire format, the shared physics (`GameConfig`) or the course lengths change;
    /// peers with different versions cannot race together. 2: the smaller tipping point and the gentler wind and
    /// lightning. 3: the time trials shortened from 150, 300 and 600 m to 15, 50 and 100 m.
    public static let protocolVersion = 3
}
