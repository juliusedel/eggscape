# Tuning

All numbers live in `GameConfig` (`Packages/EggscapeCore/Sources/EggscapeCore/Physics/GameConfig.swift`). This page
explains what they do and how the defaults were derived, so they can be changed with intent after playtesting.

## The egg in the bowl

Per axis, with position `p` (bowl units), velocity `v` and tilt `θ`:

```
a = G·sin(θ) − k·p − c·v + disturbance
```

| Constant | Default | Meaning |
|---|---|---|
| `gravity` G | 6.0 | How strongly the tilt rolls the egg. |
| `bowlStiffness` k | 2.0 | The bowl's concavity pulling the egg back to the middle. Makes small tilts forgiving. |
| `damping` c | 1.2 | Friction. Below critical damping (2·√k ≈ 2.83), so the egg overshoots and visibly wobbles. |
| `bowlRadiusX` / `bowlRadiusY` | 0.75 / 1.0 | The rim ellipse. The egg falls once `(x/0.75)² + (y/1.0)² > 1`. The bowl is longer along the handle, so tilting forwards or backwards is more forgiving than sideways. |
| `simulationRate` | 120 Hz | Fixed physics step (accumulator in `GameScene.update`). |

Derived behavior (verified in `EggPhysicsTests`):

- **Resting position** for a held tilt: `p = (G/k)·sin θ = 3·sin θ`.
- **Static fall thresholds**: sideways `3·sin θ = 0.75` → **14.5°**; along the handle `3·sin θ = 1.0` → **19.5°**.
- **Natural frequency** `ω₀ = √k ≈ 1.41 rad/s` (one wobble ≈ 4.4 s), **damping ratio** `ζ = c/(2√k) ≈ 0.42`.
- **Overshoot** after a sudden tilt: `exp(−πζ/√(1−ζ²)) ≈ 23 %`. A *sudden* tilt therefore drops the egg earlier:
  sideways from **≈ 12°**, along the handle from **≈ 16°**.
- **A single kick** `Δv` from rest peaks at `≈ 0.42·Δv` after ≈ 0.9 s. A strong footstep (0.35) moves the egg
  ≈ 0.15 units: clearly visible, never dangerous on its own.

Rules of thumb when tuning:
- Raising `k` makes everything more forgiving *and* faster; raising `G` makes tilting more sensitive without
  changing the wobble frequency.
- Lowering `c` increases the overshoot (more wobble, harder); `c = 2.83` would remove it entirely.

## Footsteps and sprinting

| Constant | Default | Meaning |
|---|---|---|
| `runSpeed` / `sprintSpeed` | 3 / 5 m/s | Auto-run and sprint speed. |
| `stepFrequency` | 2.5 Hz | Footsteps per second at run speed; scales with speed (≈ 4.2 Hz sprinting). |
| `stepKick` | 0.15 … 0.35 | Velocity kick per footstep in a random direction. |
| `sprintDisturbance` | 1.8 | Multiplier on footstep kicks while sprinting. |
| `speedResponse` | 0.25 s | How quickly the runner reaches the target speed. |

Random kicks make the egg jitter around its resting point. The stationary spread per axis is
`σ² = rate · E[Δv²]/2 / (2·c·k)`:

- running: rate 2.5/s, `E[Δv²] ≈ 0.066` → **σ ≈ 0.13** units: a level spoon practically never loses the egg.
- sprinting: rate 4.2/s, kicks × 1.8 → **σ ≈ 0.30** units: holding sprint without correcting loses an egg every
  minute or so. Sprinting saves 40 % of the time but demands active balancing. That is the intended trade-off.

## Drops and eggs

`eggsPerRun = 3`, `dropPause = 2 s` (the runner stands still while a new egg is placed).

## Tilt input

| Constant | Default | Meaning |
|---|---|---|
| `tiltFilterTimeConstant` | 50 ms | Low-pass on the gravity vector against sensor jitter (adds ~50 ms latency). |
| `deadZoneDegrees` | 0.5° | Hand tremor below this counts as level; the response stays continuous. |
| `maxTiltDegrees` | 30° | Clamp. Beyond 19.5° the egg falls anyway; the clamp keeps extreme poses from feeling "binary". |
| `sensitivityRange` | 0.7 … 1.3 | The player's setting, multiplies the calibrated tilt. |

## Weather

Intensity 1 means the values below; the "Zufall" escalation and Endlos scale intensity from 0 to 1.

| Effect | Constants | Notes |
|---|---|---|
| Wind | `windForce` 0.3 … 1.0, `gustRamp` 0.5 s, `gustHold` 1–3 s, `gustDecay` 1 s, `gustGap`, `windFlipChance` | A force `F` shifts the resting point by `F/k`: the strongest gust (1.0) pushes a level egg 0.5 units sideways, two thirds of the way to the rim; holding it needs ≈ 9.6° of counter-tilt. |
| Rain | `rainDampingFactor` 0.4, `rainDropRate`, `rainDropKick`, `puddleKick`, `puddleSpacing` | Damping drops to 0.48 (ζ ≈ 0.17, ≈ 58 % overshoot): the egg wobbles much longer and sudden corrections overshoot. Raindrops add a fine tremble; puddles one extra kick. |
| Gewitter | wind + rain + `lightningInterval` 8–15 s, `lightningWarning` 0.6 s, `lightningKick` 0.8 | A strike moves a resting egg ≈ 0.33 units, enough to drop it if the player is already fighting a gust. |

The schedule (stretches, gusts, lightning, puddles) is derived from the race seed with SplitMix64, so every player of
a race gets the same weather; see `WeatherTests`.

## Playtesting

On a device, the quickest loop is: change a constant in `GameConfig`, `make run` on the phone from Xcode, run the
150 m course twice with each weather. Record what changed here.
