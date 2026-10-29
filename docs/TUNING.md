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
| `bowlRadiusX` / `bowlRadiusY` | 0.57 / 0.76 | The tipping point. The egg falls once `(x/0.57)² + (y/0.76)² > 1`. The bowl is longer along the handle, so tilting forwards or backwards is more forgiving than sideways. |
| `simulationRate` | 120 Hz | Fixed physics step (accumulator in `GameScene.update`). |

### Why the tipping point lies inside the rim

The spoon's inner rim is 1.5 × 2 bowl units. The owner wanted a big egg in a small spoon that falls off easily, like a
real egg-and-spoon race: the egg is 1.44 units wide (1.90 tall) and nearly fills the bowl. Such an egg cannot roll
until its center reaches the steel; it rides up the wall and over the edge long before. So the tipping point was
pulled in from the rim (0.75 × 1.0) to 0.57 × 0.76, which keeps the rim's proportions and makes a steady tilt of
**11°** instead of 14.5° tip the egg. `G`, `k` and `c` are unchanged, so the egg wobbles exactly as before; it just has
less room. The scene draws the physics position scaled down to the room the big egg really has (`SceneLayout`, see
`ARCHITECTURE.md`): at the tipping point the egg hangs over the bowl's edge by a third of its half-width.

Derived behavior (verified in `EggPhysicsTests`):

- **Resting position** for a held tilt: `p = (G/k)·sin θ = 3·sin θ`.
- **Static fall thresholds**: sideways `3·sin θ = 0.57` → **11°**; along the handle `3·sin θ = 0.76` → **14.7°**.
- **Natural frequency** `ω₀ = √k ≈ 1.41 rad/s` (one wobble ≈ 4.4 s), **damping ratio** `ζ = c/(2√k) ≈ 0.42`.
- **Overshoot** after a sudden tilt: `exp(−πζ/√(1−ζ²)) ≈ 23 %`. A *sudden* tilt therefore drops the egg earlier:
  sideways from **≈ 9°**, along the handle from **≈ 12°**, diagonally (both axes) from **≈ 7°**.
- **A single kick** `Δv` from rest peaks at `≈ 0.41·Δv` after ≈ 0.9 s (`≈ 0.55·Δv` after 1 s in the wet bowl of full
  rain). A strong footstep (0.35) moves the egg ≈ 0.14 units, a quarter of the way to the tipping point: clearly
  visible, never dangerous on its own.

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

- running: rate 2.5/s, `E[Δv²] ≈ 0.066` → **σ ≈ 0.13** units, 4.4 σ from the sideways tipping point: a level spoon
  practically never loses the egg (none in 200 simulated ten-minute runs).
- sprinting: rate 4.2/s, kicks × 1.8 → **σ ≈ 0.30** units, only 1.9 σ: holding sprint without correcting loses an egg
  within seconds (median 5 s in simulation; it was half a minute with the old 0.75 rim). Sprinting saves 40 % of the
  time but demands active balancing, and an attentive player manages it (see Playability). That is the intended
  trade-off; the footsteps were kept as they were when the tipping point moved in.

## Drops and eggs

`eggsPerRun = 3`, `dropPause = 2 s` (the runner stands still while a new egg is placed).

## Tilt input

| Constant | Default | Meaning |
|---|---|---|
| `tiltFilterTimeConstant` | 50 ms | Low-pass on the gravity vector against sensor jitter (adds ~50 ms latency). |
| `deadZoneDegrees` | 0.5° | Hand tremor below this counts as level; the response stays continuous. |
| `maxTiltDegrees` | 30° | Clamp. Beyond 15° the egg falls anyway; the clamp keeps extreme poses from feeling "binary". |
| `sensitivityRange` | 0.7 … 1.3 | The player's setting, multiplies the calibrated tilt. |

## Weather

Intensity 1 means the values below; the "Zufall" escalation and Endlos scale intensity from 0 to 1.

| Effect | Constants | Notes |
|---|---|---|
| Wind | `windForce` 0.23 … 0.76, `gustRamp` 0.5 s, `gustHold` 1–3 s, `gustDecay` 1 s, `gustGap`, `windFlipChance` | A force `F` shifts the resting point by `F/k`: the strongest gust (0.76) pushes a level egg 0.38 units sideways, two thirds of the way to the tipping point; holding it needs ≈ 7.3° of counter-tilt. Scaled with the tipping point (it was 0.3 … 1.0): the old strongest gust would hold a level egg 88 % of the way out, where a footstep or 1.4° of tilt the wrong way tips it. |
| Rain | `rainDampingFactor` 0.4, `rainDropRate`, `rainDropKick`, `puddleKick`, `puddleSpacing` | Damping drops to 0.48 (ζ ≈ 0.17, ≈ 58 % overshoot): the egg wobbles much longer and sudden corrections overshoot. Raindrops add a fine tremble; puddles one extra kick. Unchanged with the tighter tipping point, so rain got harder: a level phone now loses eggs in full rain (median half a minute), an attentive player none. |
| Gewitter | wind + rain + `lightningInterval` 8–15 s, `lightningWarning` 0.6 s, `lightningKick` 0.6 | In the wet storm bowl a strike moves a resting egg ≈ 0.33 units, 58 % of the way to the sideways tipping point: enough to drop it if the player is already fighting a gust. Scaled with the tipping point like the wind (it was 0.8): at 0.8 an attentive player lost an egg in one full-storm race of twelve, at 0.6 in one of fifty. |

The schedule (stretches, gusts, lightning, puddles) is derived from the race seed with SplitMix64, so every player of
a race gets the same weather; see `WeatherTests`.

## Playability

`PlayabilityTests` plays whole runs with two simulated players and pins down that a tight tipping point is still fair:

- **Attentive**: a PD controller on the egg's position and velocity (0.6 rad per unit, 0.35 rad per unit/s), reacting
  150 ms late and never tilting more than 12°. It finishes the 150 m in calm weather without losing an egg, sprints
  through it too, and keeps at least one egg over 600 m of full thunderstorm.
- **Careless**: holds the phone level. Sprinting through the wind, it loses an egg within 20 s.

Over 200 seeds each (`RunEngine` with the defaults), the attentive player lost no egg on 150 m of calm weather nor on
600 m of wind, rain or Zufall, and one egg in 2 % of the 600 m storms; sprinting the 150 m it lost one in 0.5 % of the
runs. A sloppier player (300 ms, weaker corrections, a hand that drifts by 3°) does lose eggs in rain and storms: that
is where the tighter bowl bites. Before changing a number here, rerun such a sweep; `PlayabilityTests` shows how to
drive a run.

## Playtesting

On a device, the quickest loop is: change a constant in `GameConfig`, `make run` on the phone from Xcode, run the
150 m course twice with each weather. Record what changed here.
