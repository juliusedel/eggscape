import EggscapeCore
import SpriteKit

/// What the HUD shows; the scene publishes it a few times per second.
struct HUDSnapshot: Equatable {
    var meters = 0.0
    var elapsed = 0.0
    var eggsLeft = GameConfig.standard.eggsPerRun
    var eggsTotal = GameConfig.standard.eggsPerRun
    var courseLength: Double?
}

/// Hosts one run: advances the `RunEngine` in fixed steps from `update(_:)` and renders its state.
final class GameScene: SKScene {
    enum Mode {
        /// The egg rests in the middle; used while calibrating.
        case preview
        /// The egg already reacts to the tilt, but nothing moves yet (countdown).
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

    private(set) var engine: RunEngine
    private var timestep: FixedTimestep
    private var lastUpdate: TimeInterval?
    private var events: [RunEvent] = []
    private var hudCountdown = 0.0
    private var layout = SceneLayout(size: CGSize(width: 390, height: 844))

    private let world = PlaceholderWorldNode()
    private let spoon = PlaceholderSpoonNode()
    private let egg = PlaceholderEggNode()

    init(engine: RunEngine) {
        self.engine = engine
        timestep = FixedTimestep(rate: engine.config.simulationRate)
        super.init(size: CGSize(width: 390, height: 844))
        scaleMode = .resizeFill
        anchorPoint = .zero
        backgroundColor = SKColor(red: 0.66, green: 0.87, blue: 1, alpha: 1)
        addChild(world)
        addChild(spoon)
        addChild(egg)
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
            courseLength: engine.course.length
        )
    }

    override func didChangeSize(_: CGSize) {
        layout = SceneLayout(size: size, config: engine.config)
        world.layOut(layout)
        spoon.layOut(layout, config: engine.config)
        egg.layOut(layout)
        render()
    }

    override func update(_ currentTime: TimeInterval) {
        let frameDuration = lastUpdate.map { currentTime - $0 } ?? 0
        lastUpdate = currentTime

        switch mode {
        case .preview, .paused, .ended:
            break
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
                onEvents(events)
            }
            onFrame(engine)
            hudCountdown -= frameDuration
            if hudCountdown <= 0 || engine.isOver {
                hudCountdown = 0.1
                onHUD(hudSnapshot)
            }
        }
        render()
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
        world.render(meters: engine.meters, courseLength: engine.course.length, layout: layout)
        spoon.render(tilt: tilt)
        let hasEgg = if case .recovering = engine.phase {
            false
        } else {
            engine.phase != .over
        }
        egg.isHidden = !hasEgg
        egg.position = layout.point(inBowl: engine.egg.position)
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
}

// MARK: - Placeholder art (replaced by the final artwork)

final class PlaceholderWorldNode: SKNode {
    private let ground = SKSpriteNode(color: SKColor(red: 0.49, green: 0.79, blue: 0.35, alpha: 1), size: .zero)
    private let track = SKSpriteNode(color: SKColor(red: 0.79, green: 0.6, blue: 0.42, alpha: 1), size: .zero)
    private let runner = SKShapeNode(circleOfRadius: 14)
    private let finish = SKSpriteNode(color: .white, size: .zero)
    private var posts: [SKSpriteNode] = []

    override init() {
        super.init()
        runner.fillColor = SKColor(red: 0.95, green: 0.45, blue: 0.2, alpha: 1)
        runner.strokeColor = .clear
        [ground, track, finish, runner].forEach(addChild)
    }

    required init?(coder _: NSCoder) {
        nil
    }

    func layOut(_ layout: SceneLayout) {
        ground.anchorPoint = .zero
        ground.size = CGSize(width: layout.size.width, height: layout.trackY + 30)
        track.anchorPoint = .zero
        track.size = CGSize(width: layout.size.width, height: 26)
        track.position = CGPoint(x: 0, y: layout.trackY - 13)
        runner.position = CGPoint(x: layout.runnerX, y: layout.trackY + 14)
        finish.size = CGSize(width: 6, height: 60)
        finish.anchorPoint = CGPoint(x: 0.5, y: 0)
        posts.forEach { $0.removeFromParent() }
        let count = Int(layout.size.width / layout.pointsPerMeter / 2) + 3
        posts = (0 ..< count).map { _ in
            let post = SKSpriteNode(color: SKColor(white: 1, alpha: 0.8), size: CGSize(width: 4, height: 18))
            post.anchorPoint = CGPoint(x: 0.5, y: 0)
            addChild(post)
            return post
        }
    }

    func render(meters: Double, courseLength: Double?, layout: SceneLayout) {
        let spacing = 2.0
        let offset = meters.truncatingRemainder(dividingBy: spacing)
        for (index, post) in posts.enumerated() {
            let metersAhead = Double(index - 1) * spacing - offset
            post.position = CGPoint(x: layout.runnerX + CGFloat(metersAhead) * layout.pointsPerMeter, y: layout.trackY)
        }
        if let courseLength {
            finish.isHidden = false
            finish.position = CGPoint(
                x: layout.runnerX + CGFloat(courseLength - meters) * layout.pointsPerMeter,
                y: layout.trackY - 13
            )
        } else {
            finish.isHidden = true
        }
    }
}

final class PlaceholderSpoonNode: SKNode {
    private let handle = SKShapeNode()
    private let bowl = SKShapeNode()

    override init() {
        super.init()
        for shape in [handle, bowl] {
            shape.fillColor = SKColor(white: 0.78, alpha: 1)
            shape.strokeColor = SKColor(white: 0.55, alpha: 1)
            shape.lineWidth = 3
            addChild(shape)
        }
    }

    required init?(coder _: NSCoder) {
        nil
    }

    func layOut(_ layout: SceneLayout, config: GameConfig) {
        position = layout.bowlCenter
        let rim = CGSize(
            width: CGFloat(config.bowlRadiusX) * layout.unit.width,
            height: CGFloat(config.bowlRadiusY) * layout.unit.height
        )
        bowl.path = CGPath(
            ellipseIn: CGRect(x: -rim.width, y: -rim.height, width: rim.width * 2, height: rim.height * 2),
            transform: nil
        )
        let handleWidth = rim.width * 0.35
        handle.path = CGPath(
            roundedRect: CGRect(
                x: -handleWidth / 2,
                y: -layout.bowlCenter.y - 40,
                width: handleWidth,
                height: layout.bowlCenter.y + 40
            ),
            cornerWidth: handleWidth / 2,
            cornerHeight: handleWidth / 2,
            transform: nil
        )
    }

    func render(tilt: SIMD2<Double>) {
        // Rough stand-in for the tilt: squash the side that dips away from the viewer.
        xScale = 1 - CGFloat(abs(tilt.x)) * 0.25
        yScale = 1 - CGFloat(abs(tilt.y)) * 0.25
    }
}

final class PlaceholderEggNode: SKNode {
    private let shadow = SKShapeNode()
    private let shell = SKShapeNode()

    override init() {
        super.init()
        shadow.fillColor = SKColor(white: 0, alpha: 0.2)
        shadow.strokeColor = .clear
        shell.fillColor = SKColor(red: 1, green: 0.98, blue: 0.93, alpha: 1)
        shell.strokeColor = SKColor(white: 0.7, alpha: 1)
        addChild(shadow)
        addChild(shell)
    }

    required init?(coder _: NSCoder) {
        nil
    }

    func layOut(_ layout: SceneLayout) {
        let size = CGSize(width: layout.unit.width * 0.56, height: layout.unit.height * 0.72)
        let rect = CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)
        shell.path = CGPath(ellipseIn: rect, transform: nil)
        shadow.path = CGPath(ellipseIn: rect.offsetBy(dx: 6, dy: -8), transform: nil)
    }
}
