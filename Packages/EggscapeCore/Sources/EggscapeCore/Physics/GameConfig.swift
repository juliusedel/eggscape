/// Every tunable number of the game in one place. `docs/TUNING.md` explains how the defaults were chosen.
///
/// Positions are in normalized bowl units (the rim is an ellipse with half-axes `bowlRadiusX` × `bowlRadiusY`),
/// forces are accelerations in those units per second², kicks are velocity changes in units per second.
public struct GameConfig: Sendable, Equatable {
    // MARK: Bowl and egg

    /// Half-width of the bowl rim (sideways).
    public var bowlRadiusX = 0.75
    /// Half-length of the bowl rim along the handle (vertical on screen).
    public var bowlRadiusY = 1.0
    /// `G` in `a = G·sin(tilt) − k·p − c·v + disturbance`.
    public var gravity = 6.0
    /// `k`: restoring force of the concave bowl, makes small tilts forgiving.
    public var bowlStiffness = 2.0
    /// `c`: damping. 1.2 leaves the egg underdamped (~23 % overshoot), so it visibly wobbles.
    public var damping = 1.2
    /// Fixed simulation rate in Hz.
    public var simulationRate = 120.0

    // MARK: Tilt input

    /// Calibrated tilt is clamped to ± this angle.
    public var maxTiltDegrees = 30.0
    /// Tilt below this angle counts as level.
    public var deadZoneDegrees = 0.5
    /// Allowed range of the sensitivity setting.
    public var sensitivityRange: ClosedRange<Double> = 0.7 ... 1.3
    /// Time constant of the low-pass filter on the sensor tilt, in seconds.
    public var tiltFilterTimeConstant = 0.05

    // MARK: Running

    /// Auto-run speed in m/s.
    public var runSpeed = 3.0
    /// Speed while the sprint button is held, in m/s.
    public var sprintSpeed = 5.0
    /// Time constant with which the runner speeds up and slows down, in seconds.
    public var speedResponse = 0.25
    public var eggsPerRun = 3
    /// Seconds the runner stands still after an egg breaks.
    public var dropPause = 2.0

    // MARK: Footsteps

    /// Footsteps per second at `runSpeed`; scales with the current speed.
    public var stepFrequency = 2.5
    /// Magnitude of the velocity kick a footstep gives the egg (random direction).
    public var stepKick: ClosedRange<Double> = 0.15 ... 0.35
    /// Multiplier on footstep kicks while sprinting.
    public var sprintDisturbance = 1.8

    // MARK: Wind

    /// Peak lateral force of a gust at full intensity.
    public var windForce: ClosedRange<Double> = 0.3 ... 1.0
    public var gustRamp = 0.5
    public var gustHold: ClosedRange<Double> = 1.0 ... 3.0
    public var gustDecay = 1.0
    /// Calm seconds between two gusts.
    public var gustGap: ClosedRange<Double> = 0.5 ... 2.5
    /// Probability that the next gust blows from the other side.
    public var windFlipChance = 0.35
    /// Seconds in which the wind a runner feels follows a change of weather along the track, so running into or out
    /// of a windy stretch mid-gust never yanks the egg (gusts have their own ramp and decay).
    public var windFade = 1.0

    // MARK: Rain

    /// Multiplier on `damping` in full rain: the wet bowl gets slippery.
    public var rainDampingFactor = 0.4
    /// Raindrops hitting the egg per second at full intensity.
    public var rainDropRate = 8.0
    /// Velocity kick of a single raindrop.
    public var rainDropKick: ClosedRange<Double> = 0.02 ... 0.07
    /// Extra kick when the runner splashes through a puddle.
    public var puddleKick: ClosedRange<Double> = 0.35 ... 0.5
    /// Distance between puddles on the track, in meters.
    public var puddleSpacing: ClosedRange<Double> = 25 ... 60

    // MARK: Thunderstorm

    /// Seconds between lightning strikes.
    public var lightningInterval: ClosedRange<Double> = 8 ... 15
    /// Seconds of visual warning before a strike.
    public var lightningWarning = 0.6
    /// Velocity kick of a strike.
    public var lightningKick = 0.8

    // MARK: Weather along the track

    // Changing any weather number changes the weather every seed produces, so phones with different numbers must not
    // race together.

    /// Zufall: the first meters of a time trial are calm.
    public var randomCalmStart: ClosedRange<Double> = 20 ... 40
    /// Zufall: typical length of one stretch of weather in meters. The rest of the course is cut into about
    /// `length / randomStretchLength` stretches, at least two.
    public var randomStretchLength = 75.0
    /// Zufall: the boundaries between stretches move by up to this share of a stretch, so the stretches differ in
    /// length. Capped at 0.45 to keep the boundaries in order.
    public var randomStretchJitter = 0.3
    /// Zufall: intensity of the first stretch of weather. Later stretches get evenly stronger, up to full strength on
    /// the last one, so the hardest part is always the finish.
    public var randomStartIntensity: ClosedRange<Double> = 0.3 ... 0.5
    /// Zufall: probability that the last third of the stretches is a thunderstorm instead of wind or rain.
    public var randomStormChance = 0.6
    /// Endlos: the weather intensifies every this many meters (one stage). Stage 0 is always clear.
    public var endlessStageLength = 100.0
    /// Endlos: intensity of stage 1. Each further stage adds an equal share, so stage `1 + endlessStagesToFull` is the
    /// first at full strength: 0.3, 0.4, ... 1.0 from 800 m on with the defaults.
    public var endlessStartIntensity = 0.3
    public var endlessStagesToFull = 7
    /// Endlos: the first stage that can be a thunderstorm; earlier stages are wind or rain.
    public var endlessStormStage = 3
    /// Endlos: once the weather is at full strength, every further stage makes footsteps this much stronger ...
    public var endlessFootstepGain = 0.05
    /// ... up to this multiplier (from 1300 m on with the defaults). The cap keeps long runs hard but fair: even a
    /// sprinting footstep at the cap cannot tip the egg out of a level bowl on its own.
    public var endlessFootstepScaleMax = 1.25

    public init() {}

    public static let standard = GameConfig()
}
