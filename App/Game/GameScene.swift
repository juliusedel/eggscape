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
    private var layout = SceneLayout(size: CGSize(width: 402, height: 874))
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
    private let egg = SKSpriteNode()
    private let cameraNode = SKCameraNode()
    private var weather: WeatherOverlayNode?

    init(engine: RunEngine, appearance: EggAppearance, reduceMotion: Bool) {
        self.engine = engine
        self.appearance = appearance
        self.reduceMotion = reduceMotion
        timestep = FixedTimestep(rate: engine.config.simulationRate)
        super.init(size: CGSize(width: 402, height: 874))
        scaleMode = .resizeFill
        anchorPoint = .zero

        backdrop.zPosition = 0
        ground.zPosition = 1
        spoonShadow.zPosition = 2
        spoon.zPosition = 3
        spoonHighlight.zPosition = 4
        spoonHighlight.blendMode = .add
        eggShadow.zPosition = 5
        egg.zPosition = 6
        [backdrop, ground, spoonShadow, spoon, spoonHighlight, eggShadow, egg, cameraNode].forEach(addChild)
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
        layout = SceneLayout(size: size)
        cameraNode.position = CGPoint(x: size.width / 2, y: size.height / 2)
        weather?.layOut(size: size)
        guard let artwork, size.width > 0, size.height > 0 else { return }

        updateVignette()
        backdrop.size = size
        backdrop.position = CGPoint(x: size.width / 2, y: size.height / 2)

        // The three spoon images share one registration on the bowl center, so they are placed by it.
        let spoonLayout = artwork.spoonLayout
        let scale = layout.unit / CGFloat(spoonLayout.unit)
        let anchor = CGPoint(
            x: spoonLayout.bowlCenterX / Double(spoonLayout.width),
            y: 1 - spoonLayout.bowlCenterY / Double(spoonLayout.height)
        )
        let pixelSize = CGSize(width: spoonLayout.width, height: spoonLayout.height)
        for (node, texture) in [
            (spoon, artwork.spoon), (spoonShadow, artwork.spoonShadow), (spoonHighlight, artwork.spoonHighlight),
        ] {
            node.texture = texture
            node.anchorPoint = anchor
            node.size = CGSize(width: pixelSize.width * scale, height: pixelSize.height * scale)
            node.position = layout.bowlCenter
        }

        let eggWidth = layout.unit * GameArtwork.eggWidthUnits
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
        layout.unit * GameArtwork.eggWidthUnits * 1.7
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

    /// Screenshots and tests: simulates `seconds` of the run at once. Only the events that end the run are reported,
    /// so no burst of footstep sounds follows.
    func fastForward(seconds: Double, input: RunEngine.Input) {
        var skipped: [RunEvent] = []
        for _ in 0 ..< Int(seconds * engine.config.simulationRate) where !engine.isOver {
            engine.step(input, events: &skipped)
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

    /// Points the finger fallback at a position in the bowl (screenshots: a slightly off-center egg).
    func steer(toBowl position: SIMD2<Double>?) {
        touchSteering.target = position
    }

    private var currentInput: RunEngine.Input {
        var value = input()
        if usesTouchSteering {
            value.tilt = touchSteering.tilt
        }
        return value
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
        egg.position = layout.point(inBowl: position)
        // Rolling sideways tips the egg a little; climbing the bowl's wall brings it slightly closer to the eye.
        egg.zRotation = CGFloat(max(-0.12, min(0.12, -engine.egg.velocity.x * 0.08)))
        if egg.action(forKey: "squash") == nil, egg.action(forKey: "place") == nil {
            egg.setScale(1 + 0.05 * CGFloat(engine.egg.rimDistance * engine.egg.rimDistance))
        }
        // The light is at the top right (`Studio.shadowDirection`), so the shadow falls to the bottom left, a little
        // shorter than the egg's height would cast on a flat table because the bowl rises towards it. It stretches as
        // the egg climbs away from the center.
        let away = CGVector(dx: CGFloat(position.x) * layout.unit, dy: CGFloat(position.y) * layout.unit)
        eggShadow.position = egg.position
            + CGVector(dx: -layout.unit * 0.11, dy: -layout.unit * 0.07)
            + away * 0.08
        eggShadow.xScale = 1 + 0.3 * CGFloat(abs(position.x) / engine.config.bowlRadiusX)
        eggShadow.yScale = 1 + 0.25 * CGFloat(abs(position.y) / engine.config.bowlRadiusY)
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
        let length = max((position * position).sum().squareRoot(), 0.001)
        let landing = layout.point(inBowl: position + position / length * 0.75)
        egg.removeAction(forKey: "squash")
        egg.run(
            .sequence([
                .group([
                    .move(to: landing, duration: 0.32),
                    .scale(to: 0.6, duration: 0.32),
                    .fadeAlpha(to: 0.3, duration: 0.32),
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

    private func steer(with touches: Set<UITouch>) {
        guard usesTouchSteering, let touch = touches.first else { return }
        touchSteering.target = layout.bowlPosition(of: touch.location(in: self))
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

private func + (lhs: CGVector, rhs: CGVector) -> CGVector {
    CGVector(dx: lhs.dx + rhs.dx, dy: lhs.dy + rhs.dy)
}

private func * (lhs: CGVector, rhs: CGFloat) -> CGVector {
    CGVector(dx: lhs.dx * rhs, dy: lhs.dy * rhs)
}
