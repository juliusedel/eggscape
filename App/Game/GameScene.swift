import EggscapeArt
import EggscapeCore
import SpriteKit

/// What the HUD shows; the scene publishes it a few times per second.
struct HUDSnapshot: Equatable {
    var meters = 0.0
    var elapsed = 0.0
    var eggsLeft = GameConfig.standard.eggsPerRun
    var eggsTotal = GameConfig.standard.eggsPerRun
    var courseLength: Double?
    var weather = WeatherConditions.clear
    /// Signed lateral wind force: positive blows to the right.
    var wind = 0.0
    /// Gust strength for display, 0 ... 1.
    var gust = 0.0
}

/// Hosts one run: advances the `RunEngine` in fixed steps from `update(_:)` and renders a realistic spoon and egg
/// seen from directly above, on a white studio surface or over the live camera image.
final class GameScene: SKScene {
    enum Mode {
        /// The egg rests, in the middle before the start or where it was when a paused run is recalibrated; used while
        /// calibrating.
        case preview
        /// The egg already reacts to the tilt, but the run has not started (countdown).
        case warmUp
        case running
        case paused
        case ended
    }

    var mode = Mode.preview {
        didSet { lastUpdate = nil }
    }

    /// Supplies the calibrated tilt and sprint state for each simulation step.
    var input: () -> RunEngine.Input = { .level }
    /// Receives everything that happened during a frame.
    var onEvents: ([RunEvent]) -> Void = { _ in }
    var onHUD: (HUDSnapshot) -> Void = { _ in }
    /// Called once per rendered frame while running, e.g. for the rim-distance haptics.
    var onFrame: (RunEngine) -> Void = { _ in }
    /// Finger steering for devices without motion sensors.
    var usesTouchSteering = false
    private(set) var touchSteering = TouchSteering()
    /// Where staged screenshots keep the egg (`holdEgg(at:)`).
    private var heldPosition: SIMD2<Double>?

    /// The live camera is behind the scene: no white surface, no spoon shadow, translucent weather grading.
    var showsCamera = false {
        didSet { applyBackground() }
    }

    private(set) var engine: RunEngine
    private let appearance: EggAppearance
    private let reduceMotion: Bool
    private var timestep: FixedTimestep
    private var lastUpdate: TimeInterval?
    private var events: [RunEvent] = []
    private var hudCountdown = 0.0
    private var layout: SceneLayout
    private var artwork: GameArtwork?
    private var screenScale: CGFloat = 3
    private var shake = 0.0
    private var displayedTilt = SIMD2<Double>.zero
    private var rng = SplitMix64(seed: 0x5CE9E)

    private let backdrop = SKSpriteNode()
    private let ground = SKNode()
    private let spoonShadow = SKSpriteNode()
    private let spoon = SKSpriteNode()
    private let spoonHighlight = SKSpriteNode()
    private let eggShadow = SKSpriteNode()
    /// The egg nearly fills the bowl, so its shadow reaches past the spoon. On the white surface that is the table;
    /// over the camera image, where the spoon casts no shadow either, the shadow is cut to the spoon (`spoonMask`).
    private let eggShadowClip = SKCropNode()
    private let spoonMask = SKSpriteNode()
    private let egg = SKSpriteNode()
    /// The egg lies above the spoon and its own shadow; once it falls off, it drops below the spoon (`dropEgg`).
    private static let eggZPosition: CGFloat = 6
    private let cameraNode = SKCameraNode()
    private var weather: WeatherOverlayNode?

    init(engine: RunEngine, appearance: EggAppearance, reduceMotion: Bool) {
        self.engine = engine
        self.appearance = appearance
        self.reduceMotion = reduceMotion
        timestep = FixedTimestep(rate: engine.config.simulationRate)
        layout = SceneLayout(size: CGSize(width: 402, height: 874), config: engine.config)
        super.init(size: CGSize(width: 402, height: 874))
        scaleMode = .resizeFill
        anchorPoint = .zero

        backdrop.zPosition = 0
        ground.zPosition = 1
        spoonShadow.zPosition = 2
        spoon.zPosition = 3
        spoonHighlight.zPosition = 4
        spoonHighlight.blendMode = .add
        eggShadowClip.zPosition = 5
        eggShadowClip.addChild(eggShadow)
        egg.zPosition = Self.eggZPosition
        [backdrop, ground, spoonShadow, spoon, spoonHighlight, eggShadowClip, egg, cameraNode].forEach(addChild)
        camera = cameraNode
        applyBackground()
    }

    required init?(coder _: NSCoder) {
        nil
    }

    var hudSnapshot: HUDSnapshot {
        HUDSnapshot(
            meters: engine.meters,
            elapsed: engine.elapsed,
            eggsLeft: engine.eggsLeft,
            eggsTotal: engine.config.eggsPerRun,
            courseLength: engine.course.length,
            weather: engine.weather.conditions,
            wind: engine.weather.wind,
            gust: engine.weather.gustStrength
        )
    }

    override func didMove(to view: SKView) {
        screenScale = view.contentScaleFactor
        if artwork == nil {
            let artwork = GameArtwork.shared(screenScale: screenScale)
            self.artwork = artwork
            let overlay = WeatherOverlayNode(artwork: artwork)
            overlay.zPosition = 100
            overlay.isOverCamera = showsCamera
            cameraNode.addChild(overlay)
            weather = overlay
        }
        layOutNodes()
    }

    override func didChangeSize(_: CGSize) {
        layOutNodes()
    }

    private func applyBackground() {
        backgroundColor = showsCamera ? .clear : SKColor(red: 0.969, green: 0.965, blue: 0.953, alpha: 1)
        backdrop.isHidden = showsCamera
        spoonShadow.isHidden = showsCamera
        eggShadowClip.maskNode = showsCamera ? spoonMask : nil
        weather?.isOverCamera = showsCamera
        updateVignette()
    }

    /// The camera image hides the vignette, so it is only rendered for the white surface of a presented scene.
    private func updateVignette() {
        guard !showsCamera, view != nil, size.width > 0, size.height > 0 else { return }
        backdrop.texture = Self.vignette(size: size)
    }

    // MARK: Layout

    private func layOutNodes() {
        layout = SceneLayout(size: size, config: engine.config)
        cameraNode.position = CGPoint(x: size.width / 2, y: size.height / 2)
        weather?.layOut(size: size)
        guard let artwork, size.width > 0, size.height > 0 else { return }

        updateVignette()
        backdrop.size = size
        backdrop.position = CGPoint(x: size.width / 2, y: size.height / 2)

        // The three spoon images and the spoon-shaped mask share one registration on the bowl center, so they are
        // placed by it.
        let spoonLayout = artwork.spoonLayout
        let scale = layout.unit / CGFloat(spoonLayout.unit)
        let anchor = CGPoint(
            x: spoonLayout.bowlCenterX / Double(spoonLayout.width),
            y: 1 - spoonLayout.bowlCenterY / Double(spoonLayout.height)
        )
        let pixelSize = CGSize(width: spoonLayout.width, height: spoonLayout.height)
        for (node, texture) in [
            (spoon, artwork.spoon), (spoonShadow, artwork.spoonShadow), (spoonHighlight, artwork.spoonHighlight),
            (spoonMask, artwork.spoon),
        ] {
            node.texture = texture
            node.anchorPoint = anchor
            node.size = CGSize(width: pixelSize.width * scale, height: pixelSize.height * scale)
            node.position = layout.bowlCenter
        }

        let eggWidth = layout.unit * SceneLayout.eggWidth
        egg.texture = artwork.egg(appearance, widthPixels: Int((eggWidth * screenScale).rounded()))
        egg.size = CGSize(width: eggWidth, height: eggWidth * EggArt.aspect)
        // The shadow image is 1.5 times the egg (see `EggArt.shadow`).
        eggShadow.texture = artwork.eggShadow
        eggShadow.size = CGSize(width: eggWidth * 1.5, height: eggWidth * EggArt.aspect * 1.5)
        // Rendering the splat would stall the fall, so it is prepared now, long before the first drop.
        Task { [appearance, brokenEggPixels] in
            _ = await artwork.brokenEgg(appearance, widthPixels: brokenEggPixels)
        }
        render()
    }

    /// The splat is larger than the egg because the white runs out on the ground.
    private var brokenEggWidth: CGFloat {
        layout.unit * SceneLayout.eggWidth * 1.4
    }

    private var brokenEggPixels: Int {
        Int(brokenEggWidth * screenScale)
    }

    // MARK: Frame loop

    override func update(_ currentTime: TimeInterval) {
        let frameDuration = lastUpdate.map { currentTime - $0 } ?? 0
        lastUpdate = currentTime

        switch mode {
        case .preview, .paused:
            break
        case .ended:
            updateCamera(dt: frameDuration)
        case .warmUp:
            for _ in 0 ..< timestep.consume(frameDuration) {
                engine.warmUp(currentInput)
            }
        case .running:
            events.removeAll(keepingCapacity: true)
            for _ in 0 ..< timestep.consume(frameDuration) {
                engine.step(currentInput, events: &events)
            }
            if !events.isEmpty {
                handle(events)
                onEvents(events)
            }
            // Ending the run in `onEvents` stopped the danger haptic, the weather sounds and the emitters; going on
            // with this frame would start them again for good.
            guard mode == .running else { break }
            onFrame(engine)
            weather?.update(weather: engine.weather, dt: frameDuration)
            hudCountdown -= frameDuration
            if hudCountdown <= 0 || engine.isOver {
                hudCountdown = 0.1
                onHUD(hudSnapshot)
            }
            updateCamera(dt: frameDuration)
        }
        render()
    }

    /// Screenshots and tests: simulates `seconds` of the run at once with the usual steering, e.g. `holdEgg(at:)`. Only
    /// the events that end the run are reported, so no burst of footstep sounds follows.
    func fastForward(seconds: Double) {
        var skipped: [RunEvent] = []
        for _ in 0 ..< Int(seconds * engine.config.simulationRate) where !engine.isOver {
            engine.step(currentInput, events: &skipped)
        }
        let endings = skipped.filter { event in
            switch event {
            case .finished, .runOver: true
            default: false
            }
        }
        if !endings.isEmpty {
            handle(endings)
            onEvents(endings)
        }
        onHUD(hudSnapshot)
        render()
    }

    /// Screenshots: keeps the egg at a physics position in the bowl, e.g. slightly off center, instead of the player's
    /// tilt or finger; `nil` lets go. It tilts the spoon against every wobble, as a quick and attentive player would: a
    /// fixed tilt would leave the egg to the weather, which tips it off the spoon within seconds in rain or a storm.
    func holdEgg(at position: SIMD2<Double>?) {
        heldPosition = position
    }

    private var currentInput: RunEngine.Input {
        var value = input()
        if let heldPosition {
            value.tilt = tilt(holding: heldPosition)
        } else if usesTouchSteering {
            value.tilt = touchSteering.tilt
        }
        return value
    }

    /// The tilt that keeps the egg at `target`: the finger fallback's tilt, at which it would rest there, corrected by
    /// 1 radian per unit the egg is off and 0.8 per unit per second it rolls (a PD controller, about critically damped
    /// on top of the bowl's own pull and damping).
    private func tilt(holding target: SIMD2<Double>) -> SIMD2<Double> {
        let rolling = engine.egg
        let tilt = TouchSteering(config: engine.config, target: target).tilt
            - (rolling.position - target) - 0.8 * rolling.velocity
        let limit = engine.config.maxTiltDegrees * .pi / 180
        return SIMD2(min(max(tilt.x, -limit), limit), min(max(tilt.y, -limit), limit))
    }

    private func render() {
        let tilt = mode == .preview ? .zero : currentInput.tilt
        // Smoothing keeps sensor noise from making the reflections flicker.
        displayedTilt += (tilt - displayedTilt) * 0.2
        spoonHighlight.position = layout.bowlCenter + CGVector(
            dx: -CGFloat(displayedTilt.x) * layout.unit * 0.35,
            dy: -CGFloat(displayedTilt.y) * layout.unit * 0.35
        )
        spoonHighlight.alpha = engine.weather.isRaining ? 1 : 0.85

        guard egg.action(forKey: "fall") == nil else { return }
        let hasEgg = if case .recovering = engine.phase {
            false
        } else {
            engine.phase != .over
        }
        egg.isHidden = !hasEgg
        eggShadow.isHidden = !hasEgg
        guard hasEgg else { return }

        let position = engine.egg.position
        let offset = layout.eggOffset(for: position)
        egg.position = layout.point(inBowl: offset)
        // Rolling sideways tips the egg a little; riding up onto the rim brings it slightly closer to the eye.
        egg.zRotation = CGFloat(max(-0.12, min(0.12, -engine.egg.velocity.x * 0.08)))
        if egg.action(forKey: "squash") == nil, egg.action(forKey: "place") == nil {
            egg.setScale(1 + 0.05 * CGFloat(engine.egg.rimDistance * engine.egg.rimDistance))
        }
        // The shadow stretches and moves out a little further as the egg climbs away from the center.
        eggShadow.position = egg.position + layout.vector(inBowl: SceneLayout.eggShadowOffset + offset * 0.08)
        let climb = position / layout.tippingPoint
        eggShadow.xScale = 1 + 0.3 * CGFloat(abs(climb.x))
        eggShadow.yScale = 1 + 0.25 * CGFloat(abs(climb.y))
        if eggShadow.action(forKey: "fade") == nil {
            eggShadow.alpha = 1 - 0.25 * CGFloat(engine.egg.rimDistance)
        }
    }

    // MARK: Events

    private func handle(_ events: [RunEvent]) {
        for event in events {
            switch event {
            case let .kick(kick) where kick.source != .footstep:
                squash(along: kick.velocity)
                shake = max(shake, kick.source == .lightning ? 1 : 0.6)
            case .lightningWarning:
                weather?.lightningWarning()
            case .lightningStrike:
                weather?.lightningStrike()
            case let .eggDropped(position, _):
                dropEgg(from: position)
            case .newEgg:
                placeNewEgg()
            case .finished, .runOver:
                weather?.clear()
            default:
                break
            }
        }
    }

    private func squash(along velocity: SIMD2<Double>) {
        let magnitude = CGFloat(min((velocity * velocity).sum().squareRoot(), 1))
        egg.removeAction(forKey: "squash")
        egg.run(
            .sequence([
                .group([
                    .scaleX(to: 1 + 0.08 * magnitude, duration: 0.05),
                    .scaleY(to: 1 - 0.07 * magnitude, duration: 0.05),
                ]),
                .group([.scaleX(to: 1, duration: 0.18), .scaleY(to: 1, duration: 0.18)]),
            ]),
            withKey: "squash"
        )
    }

    /// The egg rolls over the rim, falls off the spoon and smashes on the ground below.
    private func dropEgg(from position: SIMD2<Double>) {
        // On from where the egg was drawn, over the edge and down beside the spoon.
        let landing = layout.point(inBowl: SceneLayout.landing(ofEggFallingFrom: layout.eggOffset(for: position)))
        let underSpoon = (spoonShadow.zPosition + spoon.zPosition) / 2
        egg.removeAction(forKey: "squash")
        egg.run(
            .sequence([
                .group([
                    .move(to: landing, duration: 0.32),
                    .scale(to: CGFloat(SceneLayout.fallenEggScale), duration: 0.32),
                    // Once over the rim it drops below it, and the steel hides what is still over the bowl. It only
                    // fades after that, so the steel never shows through it.
                    .sequence([.wait(forDuration: 0.1), .run { [weak egg] in egg?.zPosition = underSpoon }]),
                    .sequence([.wait(forDuration: 0.16), .fadeAlpha(to: 0.3, duration: 0.16)]),
                ]),
                .hide(),
                .fadeAlpha(to: 1, duration: 0),
            ]),
            withKey: "fall"
        )
        eggShadow.run(.fadeOut(withDuration: 0.15), withKey: "fade")

        guard let artwork else { return }
        let width = brokenEggWidth
        // Clear until the texture is set, which it normally is long before the splat fades in.
        let broken = SKSpriteNode(color: .clear, size: CGSize(width: width, height: width * 0.8))
        Task { [weak broken, appearance, brokenEggPixels] in
            // Awaited first: `broken?.texture = await …` would hold the node strongly while the texture renders.
            let texture = await artwork.brokenEgg(appearance, widthPixels: brokenEggPixels)
            broken?.texture = texture
        }
        broken.position = landing
        broken.zRotation = CGFloat(rng.uniform(-Double.pi ... Double.pi))
        broken.setScale(0.7)
        broken.alpha = 0
        let appear = SKAction.sequence([.wait(forDuration: 0.3), .fadeIn(withDuration: 0.05)])
        // Over the moving real ground a splat cannot stay put, so in camera mode it fades away again.
        broken.run(showsCamera
            ? .sequence([appear, .wait(forDuration: 2), .fadeOut(withDuration: 0.6), .removeFromParent()])
            : appear)
        ground.addChild(broken)
        run(.wait(forDuration: 0.3)) { [weak self] in
            guard let self else { return }
            shake = max(shake, 0.5)
        }
    }

    /// A fresh egg is set down into the bowl from above.
    private func placeNewEgg() {
        egg.removeAction(forKey: "fall")
        egg.zPosition = Self.eggZPosition
        egg.isHidden = false
        egg.alpha = 0
        egg.setScale(1.25)
        egg.run(.group([.fadeIn(withDuration: 0.2), .scale(to: 1, duration: 0.28)]), withKey: "place")
        eggShadow.removeAction(forKey: "fade")
        eggShadow.alpha = 0
        eggShadow.run(.fadeAlpha(to: 1, duration: 0.28), withKey: "fade")
    }

    // MARK: Camera

    /// A very subtle bob with the footsteps and a short shake on puddles, lightning and drops.
    private func updateCamera(dt: Double) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        guard !reduceMotion else {
            cameraNode.position = center
            return
        }
        let bobAmplitude: CGFloat = engine.phase == .running ? (engine.isSprinting ? 2.4 : 1.2) : 0
        let bob = sin(CGFloat(engine.stepPhase) * 2 * .pi) * bobAmplitude
        shake = max(shake - dt * 3, 0)
        let jitter = CGFloat(shake * shake) * 7
        cameraNode.position = CGPoint(
            x: center.x + CGFloat(rng.uniform(-1 ... 1)) * jitter,
            y: center.y + bob + CGFloat(rng.uniform(-1 ... 1)) * jitter
        )
    }

    // MARK: Touch steering

    override func touchesBegan(_ touches: Set<UITouch>, with _: UIEvent?) {
        steer(with: touches)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with _: UIEvent?) {
        steer(with: touches)
    }

    override func touchesEnded(_: Set<UITouch>, with _: UIEvent?) {
        touchSteering.target = nil
    }

    override func touchesCancelled(_: Set<UITouch>, with _: UIEvent?) {
        touchSteering.target = nil
    }

    /// The egg comes to rest where it is drawn under the finger.
    private func steer(with touches: Set<UITouch>) {
        guard usesTouchSteering, let touch = touches.first else { return }
        touchSteering.target = layout.eggPosition(forOffset: layout.bowlPosition(of: touch.location(in: self)))
    }

    // MARK: Helpers

    /// The vignette of the last scene size; every scene has the screen's size.
    private static var vignetteCache: (size: CGSize, texture: SKTexture)?

    /// A barely visible radial vignette that keeps the white surface from looking flat. The gradient is so smooth that
    /// one pixel per 16 points, stretched by the sprite with SpriteKit's linear filtering, looks like a full render.
    static func vignette(size: CGSize) -> SKTexture {
        if let cached = vignetteCache, cached.size == size {
            return cached.texture
        }
        let pixels = CGSize(width: (size.width / 16).rounded(.up), height: (size.height / 16).rounded(.up))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: pixels, format: format).image { context in
            // Drawn in points, so the gradient is round again once the sprite stretches the image to `size`.
            context.cgContext.scaleBy(x: pixels.width / size.width, y: pixels.height / size.height)
            UIColor(red: 0.969, green: 0.965, blue: 0.953, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let colors = [UIColor(white: 1, alpha: 0.55).cgColor, UIColor(white: 0.5, alpha: 0.09).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [
                0,
                1,
            ]) {
                let center = CGPoint(x: size.width * 0.58, y: size.height * 0.38)
                context.cgContext.drawRadialGradient(
                    gradient,
                    startCenter: center,
                    startRadius: 0,
                    endCenter: center,
                    endRadius: max(size.width, size.height) * 0.75,
                    options: [.drawsAfterEndLocation]
                )
            }
        }
        let texture = SKTexture(image: image)
        vignetteCache = (size, texture)
        return texture
    }
}

private func + (lhs: CGPoint, rhs: CGVector) -> CGPoint {
    CGPoint(x: lhs.x + rhs.dx, y: lhs.y + rhs.dy)
}
