# Eggscape

A digital "Eierlauf" (egg-and-spoon race) for iPhone. **The phone is the spoon:** a realistic egg lies in a real
stainless-steel spoon seen from above. Tilt the phone gently to keep the egg in the bowl while your run counts the
meters; tilt too far and it rolls over the rim and breaks.

## How to play

1. Hold the phone flat in front of you like a spoon and tap **Kalibrieren**: that pose counts as level.
2. After "3, 2, 1, Los!" you run automatically. Every footstep makes the egg wobble.
3. Keep the egg in the middle with small tilts. The phone buzzes stronger the closer the egg gets to the rim.
4. Hold **Sprint** to run faster, at the price of a much shakier egg.
5. Three eggs per run. Wind pushes the egg sideways, rain makes the spoon slippery, a thunderstorm adds lightning.

Modes: **Zeitrennen** (15 / 50 / 100 m), **Endlos** (weather gets rougher every 100 m), **Gemeinsam an einem
Handy** (2–4 players, pass the phone), **In der Nähe** (2–4 phones in the same room, no internet). Coins earned while
playing buy egg skins in the **Shop**; coin packs are also sold as in-app purchases. **Bestenliste** shows personal
bests and Game Center leaderboards. Backgrounds: white studio surface or the live rear camera ("see-through phone").

## Setup

```bash
brew install xcodegen swiftformat fastlane   # or: make bootstrap (builds XcodeGen + SwiftFormat from source)
make gen                                     # generates Eggscape.xcodeproj from project.yml (never edit it)
make run                                     # builds and launches the app on an iPhone simulator
```

In the Simulator there are no motion sensors: drag the egg with a finger instead.

| Command | What it does |
|---|---|
| `make test` | EggscapeCore tests (`swift test`) and the app unit tests on a simulator |
| `make test-ui` | UI tests, including a complete 15 m time trial |
| `make build` | Unsigned simulator build (what CI runs) |
| `make format` / `make lint` | SwiftFormat |
| `make art` | Re-renders the spoon images into the asset catalog |
| `make sounds` | Re-synthesizes the sound effects |
| `make icon` | Re-renders the app icon |
| `make beta` / `make release` / `make screenshots` | fastlane lanes, see `docs/RELEASE.md` |
| `make screenshots-sim` | App Store screenshots with simctl alone, no fastlane or UI tests |
| `make site-check` | Checks the support and privacy pages in `site/` before they go live |

## Architecture

```
Packages/EggscapeCore     pure Swift, tested with `swift test`
  EggscapeCore            physics, run engine, weather schedule, seeded RNG, multiplayer messages,
                          shop economy, leaderboard ids
  EggscapeArt             procedural photo-realistic textures (egg skins, spoon, effects)
  eggscape-art            command line tool that writes the spoon assets and preview sheets
App/                      SwiftUI menus + SpriteKit game scene
  Sensors/                CoreMotion tilt (100 Hz, low-pass), calibration, finger fallback
  Game/                   GameScene (fixed 120 Hz steps from SKScene.update), RunSession, launcher
  Feedback/               CoreHaptics and synthesized sounds
  Camera/                 rear camera background
  Persistence/            settings, personal bests, wallet (UserDefaults)
  Store/  GameCenter/     StoreKit 2 coin packs, Game Center leaderboards
  Multiplayer/            transport protocol, MultipeerConnectivity, lobby and race coordination
  Features/               tabs: Einzelspieler, Mehrspieler, Bestenliste, Shop; settings, tutorial, run overlays
```

The physics run on a fixed timestep inside `RunEngine`, a plain value type that never reads a clock, so every rule
(thresholds, weather, finish order) is unit-tested in `EggscapeCore`. The weather of a race is derived from its seed,
so all phones in a multiplayer race see the same gusts and lightning. See `docs/ARCHITECTURE.md` for the module
contracts, `docs/TUNING.md` for the physics, `docs/TESTING.md` for the device checklist, `docs/RELEASE.md` for the
path to the App Store and `docs/ASSUMPTIONS.md` for every decision taken without asking.

No accounts of our own, no backend, no analytics, no ads, no tracking, no third-party SDKs.
