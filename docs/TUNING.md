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
| `deadZoneDegrees` | 0.5° | Hand tremor below this counts as level; the response stays continuous. Measured on the phone, before the gain. |
| `tiltGain` | 2.5 | Base gain: the egg feels the phone's tilt beyond the dead zone two and a half times as strongly. |
| `maxTiltDegrees` | 30° | Clamp on the tilt the egg feels. Beyond 15° the egg falls anyway; the clamp keeps extreme poses from feeling "binary". |
| `sensitivityRange` | 0.7 … 1.3 | The player's setting (Einstellungen → Empfindlichkeit, 70–130 %), multiplies the gain. |

`TiltCalibration` turns the phone's tilt `φ` (relative to the calibrated pose) into the tilt the egg feels:
`θ = min((|φ| − 0.5°) · tiltGain · sensitivity, 30°)` with the sign of `φ`, and 0 inside the dead zone. Every angle
elsewhere on this page (tipping points, the simulated players of Playability) is `θ`.

**Why a gain of 2.5 (owner, 2026-10-29).** With the gain at 1 the owner found the egg too sluggish: it took a big turn
of the wrist to move it, and the tipping point lay at 11.5° of phone tilt. The owner asked for the default to steer
2.5 times as strongly while the slider stays as it is, so the gain sits in front of the setting instead of moving
its range: 100 % still is the recommended steering, and stored settings keep their meaning. At 100 % the phone now
tips the egg sideways at about **4.9°** (`0.5° + 11°/2.5`) and along the handle at about **6.4°** (`0.5° + 14.7°/2.5`),
a sudden tilt at about 4.1° and 5.3°; at 70 % at about 6.8° and 8.9°, at 130 % at about 3.9° and 5.0°. The clamp is
reached at 12.5° of phone tilt, where the egg has long fallen, so it still only tames extreme poses. The dead zone
stays at 0.5° of the phone: it is applied before the gain, so it swallows the same tremor as before; a bigger one
would swallow the small corrections that the stronger steering is about. The gain only maps one phone's hand to its
own egg (the race sees `θ`), so phones with different gains can race together and the protocol version stays.
Finger steering in the Simulator (`TouchSteering`) computes `θ` from the finger directly and is not affected.

## Weather

Intensity 1 means the values below; the "Zufall" escalation and Endlos scale intensity from 0 to 1.

| Effect | Constants | Notes |
|---|---|---|
| Wind | `windForce` 0.23 … 0.76, `gustRamp` 0.5 s, `gustHold` 1–3 s, `gustDecay` 1 s, `gustGap`, `windFlipChance` | A force `F` shifts the resting point by `F/k`: the strongest gust (0.76) pushes a level egg 0.38 units sideways, two thirds of the way to the tipping point; holding it needs ≈ 7.3° of counter-tilt. Scaled with the tipping point (it was 0.3 … 1.0): the old strongest gust would hold a level egg 88 % of the way out, where a footstep or 1.4° of tilt the wrong way tips it. |
| Rain | `rainDampingFactor` 0.4, `rainDropRate`, `rainDropKick`, `puddleKick`, `puddleSpacing` | Damping drops to 0.48 (ζ ≈ 0.17, ≈ 58 % overshoot): the egg wobbles much longer and sudden corrections overshoot. Raindrops add a fine tremble; puddles one extra kick. Unchanged with the tighter tipping point, so rain got harder: a level phone now loses eggs in full rain (median half a minute), an attentive player none. |
| Gewitter | wind + rain + `lightningInterval` 8–15 s, `lightningWarning` 0.6 s, `lightningKick` 0.6 | In the wet storm bowl a strike moves a resting egg ≈ 0.33 units, 58 % of the way to the sideways tipping point: enough to drop it if the player is already fighting a gust. Scaled with the tipping point like the wind (it was 0.8): at 0.8 an attentive player lost an egg in one 600 m full-storm race of twelve, at 0.6 in one of fifty. |

The HUD's wind arrow, the wind sound, the slant of the rain and the blowing leaves follow the gust's share of the
strongest one (`WeatherSystem.gustStrength`), not its force, so retuning `windForce` keeps them as they are.

The schedule (stretches, gusts, lightning, puddles) is derived from the race seed with SplitMix64, so every player of
a race gets the same weather; see `WeatherTests`.

### On the courses

The weather was tuned when the time trials were 150, 300 and 600 m long and stayed as it was when they became 15, 50
and 100 m (5.2, 16.9 and 33.6 s at running speed). Shorter courses see less of it:

- **Zufall** starts calm for 20–40 m, but for at most half the course (`WeatherSchedule.escalatingStretches`): 7.5 m
  of the 15 m, 20–25 m of the 50 m, 20–40 m of the 100 m. The rest (7.5 m, 25–30 m or 60–80 m) would be cut into
  stretches of about `randomStretchLength` (75 m), but never into fewer than two, so every course gets exactly two,
  and `randomStretchLength` has no effect on the time trials unless it drops below about 32 m. The two are wind or
  rain at 0.3–0.5, then the finale at full strength, a thunderstorm in 59 % of the seeds. The finale begins 10–12 m
  into the 15 m, 31–41 m into the 50 m and 48–79 m into the 100 m.
- **Lightning** strikes 8 to 15 s apart, counted from race time 0 (`LightningTimeline`), and reaches a runner only in
  a thunderstorm. So a 15 m run is over before the first strike, even after a broken egg (7.5 s); only a runner who
  breaks two eggs (9.7 s) can still meet one: a level phone did in 0.6 % of 2,000 simulated 15 m storms, the attentive
  player never. A full storm brings one strike over 50 m (two in under 1 % of the seeds) and two to four over 100 m
  (2.4 on average); Zufall strikes in 16 % of the 50 m races and half of the 100 m ones.
- **Puddles** lie 25 to 60 m apart, counted from the start line (`PuddleTrack`), and hold water only where it rains:
  none on 15 m, one on 50 m for 71 % of the seeds, one to three on 100 m (two for 78 %).
- **Gusts** blow 2.5–4.5 s with calm gaps of 0.5–2.5 s, so even the 15 m course sees one or two.

Endlos is unchanged: its weather follows the meters run, not the courses.

## Playability

`PlayabilityTests` plays whole runs with two simulated players and pins down that a tight tipping point is still fair:

- **Attentive**: a PD controller on the egg's position and velocity (0.6 rad per unit, 0.35 rad per unit/s), reacting
  150 ms late and never tilting more than 12°. It finishes the 15 m in calm weather without losing an egg, sprints
  the 100 m (about 20 s) without losing one either, keeps at least one egg in a full thunderstorm on every course, and
  also through 200 s of full thunderstorm without a finish line, as long as the old 600 m course took, so the
  endurance check does not shrink with the courses.
- **Careless**: holds the phone level. Sprinting through the wind, it loses an egg within 20 s.

Over 200 seeds each (`RunEngine` with the defaults), the attentive player lost no egg on 15 m of calm weather,
sprinting (3.2 s) or not (5.2 s), nor on 100 m of wind, rain, Zufall or thunderstorm. Sprinting the 100 m in calm
weather (20.2 s) it lost one egg in 2,000 runs, where a level phone loses one in more than nine runs of ten. Through
200 s of full thunderstorm it lost one egg in 2 % of the runs, the first after 77 s at the earliest, which is what
the old 600 m storm cost. A sloppier player (300 ms, corrections of 0.4 rad per unit and 0.2 rad per unit/s, a hand
that drifts slowly by up to 3°) loses an egg in 20 % of the 100 m storms, 6 % of the 50 m storms, 5.5 % of the
100 m Zufall races and 0.5 % of the 15 m storms, but none in wind or rain on any course; it takes 200 s of rain to
cost it an egg (3 %) and 200 s of storm costs it one in 74 % of the runs. So on the new courses the tighter bowl
bites in thunderstorms, and in rain only over longer runs such as Endlos. Before changing a number here, rerun such
a sweep; `PlayabilityTests` shows how to drive a run.

## Playtesting

On a device, the quickest loop is: change a constant in `GameConfig`, `make run` on the phone from Xcode, run the
100 m course twice with each weather (the 15 m course has no puddles and is over before the first strike). Record what
changed here.
