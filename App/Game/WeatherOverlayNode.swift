import EggscapeCore
import SpriteKit

/// How lightning lights up the screen. Normally two quick flickers warn of a strike, which then turns the picture
/// almost white and fades fast. With Dim Flashing Lights (iOS Settings → Accessibility → Motion) nothing flickers or
/// jumps: the picture brightens a little and slowly while a strike approaches, so the warning stays, and the strike
/// lifts it to about a third and fades slowly. The thunder and the push on the egg stay the same.
struct LightningFlash: Equatable {
    /// Two quick flickers warn of a strike; otherwise the picture slowly brightens to `warningGlow`.
    var flickers: Bool
    /// Opacity of the white the picture slowly brightens to before a strike, when it does not flicker.
    var warningGlow: CGFloat
    /// Opacity of the white at the strike.
    var strikeOpacity: CGFloat
    /// Seconds the strike takes to get there; 0 is a flash.
    var strikeRise: TimeInterval
    /// Seconds the strike takes to fade.
    var strikeFade: TimeInterval

    static let standard = LightningFlash(
        flickers: true,
        warningGlow: 0,
        strikeOpacity: 0.9,
        strikeRise: 0,
        strikeFade: 0.35
    )
    static let dimmed = LightningFlash(
        flickers: false,
        warningGlow: 0.1,
        strikeOpacity: 0.3,
        strikeRise: 0.15,
        strikeFade: 0.9
    )

    /// - Parameter dimsFlashingLights: the player's Dim Flashing Lights setting (`MADimFlashingLightsEnabled()`).
    static func forSetting(dimsFlashingLights: Bool) -> LightningFlash {
        dimsFlashingLights ? .dimmed : .standard
    }
}

/// Screen-fixed weather effects on top of the spoon: color grading, rain streaks, drops landing on the spoon, blowing
/// leaves and lightning. It is attached to the camera, so it does not bob or shake with the spoon.
final class WeatherOverlayNode: SKNode {
    private let grading = SKSpriteNode(color: .black, size: .zero)
    private let flash = SKSpriteNode(color: .white, size: .zero)
    private let rain = SKEmitterNode()
    private let leaves = SKEmitterNode()
    private let drops = SKNode()
    private let raindrops: [SKTexture]
    private var size = CGSize.zero
    private var dropBudget = 0.0
    private var rng = SplitMix64(seed: 0xD20B)
    private let lightning: LightningFlash

    /// Over the camera image the grading is a translucent overlay and needs to be a little stronger to be seen.
    var isOverCamera = false

    init(artwork: GameArtwork, lightning: LightningFlash) {
        raindrops = artwork.raindrops
        self.lightning = lightning
        super.init()
        grading.alpha = 0
        grading.zPosition = 0
        addChild(grading)

        drops.zPosition = 1
        addChild(drops)

        rain.particleTexture = artwork.streak
        rain.particleBirthRate = 0
        rain.particleLifetime = 0.55
        rain.particleLifetimeRange = 0.2
        rain.particleAlpha = 0.3
        rain.particleAlphaRange = 0.12
        rain.particleScaleRange = 0.45
        rain.particleSpeed = 1500
        rain.particleSpeedRange = 300
        rain.emissionAngle = -.pi / 2
        rain.zPosition = 2
        addChild(rain)

        leaves.particleTexture = artwork.leaf
        leaves.particleBirthRate = 0
        leaves.particleLifetime = 2.2
        leaves.particleLifetimeRange = 0.8
        leaves.particleSpeed = 520
        leaves.particleSpeedRange = 160
        leaves.particleRotationRange = .pi * 2
        leaves.particleRotationSpeed = 2.5
        leaves.particleScaleRange = 0.5
        leaves.particleAlpha = 0.95
        leaves.emissionAngleRange = 0.5
        leaves.zPosition = 3
        addChild(leaves)

        flash.alpha = 0
        flash.blendMode = .add
        flash.zPosition = 4
        addChild(flash)
    }

    required init?(coder _: NSCoder) {
        nil
    }

    func layOut(size: CGSize) {
        self.size = size
        grading.size = size
        flash.size = size
        rain.position = CGPoint(x: 0, y: size.height / 2 + 40)
        rain.particlePositionRange = CGVector(dx: size.width * 1.4, dy: 0)
        leaves.particlePositionRange = CGVector(dx: 0, dy: size.height * 0.9)
    }

    /// Follows the weather where the runner is; called every frame while running.
    func update(weather: WeatherSystem, dt: Double) {
        let mix = weather.mix
        // Wet weather cools and darkens the picture, a thunderstorm much more.
        let target = CGFloat(0.16 * mix.rain + 0.2 * mix.lightning) * (isOverCamera ? 1.3 : 1)
        grading.color = mix.lightning > 0
            ? SKColor(red: 0.05, green: 0.07, blue: 0.16, alpha: 1)
            : SKColor(red: 0.12, green: 0.18, blue: 0.28, alpha: 1)
        grading.alpha += (target - grading.alpha) * CGFloat(min(dt * 1.5, 1))

        rain.particleBirthRate = weather.isRaining ? CGFloat(60 + 140 * mix.rain) : 0
        // By the gust's share of the strongest one, so retuning the wind's force does not change the picture.
        let gust = weather.wind < 0 ? -weather.gustStrength : weather.gustStrength
        rain.emissionAngle = -.pi / 2 + CGFloat(gust) * 0.18

        let windy = mix.wind > 0 && weather.gustStrength > 0.05
        leaves.particleBirthRate = windy ? CGFloat(1.5 + 9 * weather.gustStrength) : 0
        let fromLeft = weather.wind > 0
        leaves.position = CGPoint(x: fromLeft ? -size.width / 2 - 30 : size.width / 2 + 30, y: 0)
        leaves.emissionAngle = fromLeft ? 0 : .pi

        if weather.isRaining {
            spawnDrops(rate: 2 + 4 * mix.rain, dt: dt)
        }
    }

    /// The warning before a strike: a short double flicker, or a slow glow that fades again unless the strike takes
    /// over from it.
    func lightningWarning() {
        flash.removeAction(forKey: "flash")
        let warning: SKAction = lightning.flickers
            ? .sequence([
                .fadeAlpha(to: 0.12, duration: 0.05), .fadeAlpha(to: 0, duration: 0.12),
                .wait(forDuration: 0.12),
                .fadeAlpha(to: 0.18, duration: 0.05), .fadeAlpha(to: 0, duration: 0.15),
            ])
            : .sequence([
                .fadeAlpha(to: lightning.warningGlow, duration: 0.45),
                .wait(forDuration: 0.3),
                .fadeAlpha(to: 0, duration: 0.5),
            ])
        flash.run(warning, withKey: "flash")
    }

    func lightningStrike() {
        flash.removeAction(forKey: "flash")
        flash.run(
            .sequence([
                .fadeAlpha(to: lightning.strikeOpacity, duration: lightning.strikeRise),
                .fadeAlpha(to: 0, duration: lightning.strikeFade),
            ]),
            withKey: "flash"
        )
    }

    /// Stops all weather, e.g. when the run is over.
    func clear() {
        rain.particleBirthRate = 0
        leaves.particleBirthRate = 0
        drops.children.forEach { $0.run(.sequence([.fadeOut(withDuration: 0.6), .removeFromParent()])) }
        grading.run(.fadeAlpha(to: 0, duration: 0.8))
    }

    /// Water drops landing on the spoon and the "lens": they appear quickly and dry off slowly.
    private func spawnDrops(rate: Double, dt: Double) {
        dropBudget += rate * dt
        while dropBudget >= 1, drops.children.count < 28, !raindrops.isEmpty {
            dropBudget -= 1
            let drop = SKSpriteNode(texture: raindrops[rng.index(below: raindrops.count)])
            drop.setScale(CGFloat(rng.uniform(0.5 ... 1.15)))
            drop.position = CGPoint(
                x: CGFloat(rng.uniform(-0.48 ... 0.48)) * size.width,
                y: CGFloat(rng.uniform(-0.42 ... 0.38)) * size.height
            )
            drop.alpha = 0
            drop.run(.sequence([
                .fadeAlpha(to: 0.95, duration: 0.06),
                .wait(forDuration: rng.uniform(1.5 ... 3.5)),
                .fadeOut(withDuration: 1.2),
                .removeFromParent(),
            ]))
            drops.addChild(drop)
        }
        dropBudget = min(dropBudget, 1)
    }
}
