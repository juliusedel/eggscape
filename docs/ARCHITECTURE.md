# Architecture

Eggscape is a native iPhone game: a digital "Eierlauf" (egg-and-spoon race). The phone *is* the spoon. The player
tilts it to keep a realistic egg in a realistic spoon seen from directly above, while the run counts meters.

This document is the contract between the modules. Change it together with the code.

## Product decisions (owner, 2026-10-27)

The original build spec asked for a cartoon meadow with parallax layers. The owner replaced that direction:

- **Realistic look, calm presentation.** A real stainless-steel spoon and a photo-realistic egg, seen from directly
  above. No runner figure, no scrolling landscape, no cartoon outlines. Motion comes from the egg itself.
- **Two backgrounds:** *Weiß* (a white studio surface with soft shadows, like a product photo) and *Kamera* (the
  live rear camera, so the player looks "through" the phone at the ground they are running on).
- **Egg skins** (dyed, patterned, pearl, metallic eggs) in a **shop**. Skins cost **coins earned by playing**;
  **coin packs** are also sold as consumable **in-app purchases** (StoreKit 2).
- **Global leaderboards via Game Center** (no own backend).
- **Tab bar** at the bottom: *Einzelspieler*, *Mehrspieler*, *Bestenliste*, *Shop*. Settings and the tutorial are
  reached from a toolbar button.

Everything else in the original spec still applies: physics, weather (Wind, Regen, Gewitter), Zeitrennen, Endlos,
Hot-Seat, Nearby multiplayer, haptics, audio, localization (German base, English), accessibility, App Store package.

## Modules

```
Packages/EggscapeCore/            Swift package, no UIKit/SpriteKit/SwiftUI
  Sources/EggscapeCore/           game logic
    Physics/                      EggPhysics, GameConfig, FixedTimestep
    Race/                         RunEngine, Course, RunEvent
    Random/                       SplitMix64
    Weather/                      WeatherTypes, WeatherSchedule, WeatherSystem
    Net/                          multiplayer wire format, clock sync, referee
    Economy/                      EggAppearance, skin catalog, coin rewards, wallet, coin packs
    Leaderboard/                  Game Center leaderboard IDs and score encoding
  Sources/EggscapeArt/            procedural, photo-realistic textures (pure Swift, Foundation only)
  Sources/eggscape-art/           macOS command line tool: renders assets and preview sheets as PNG
  Tests/...
App/                              iOS app target "Eggscape"
  Sensors/                        CoreMotion input, calibration, finger fallback
  Game/                           GameScene (SpriteKit), nodes, texture cache, RunSession
  Camera/                         rear camera background
  Feedback/                       haptics (CoreHaptics), sounds
  Persistence/                    settings, personal bests, wallet (UserDefaults)
  Store/                          StoreKit 2 coin packs
  GameCenter/                     authentication, leaderboards, score submission
  Multiplayer/                    transport protocol, MultipeerConnectivity, lobby and race coordination
  Features/                       SwiftUI screens (tabs, setup, run overlays, results, shop, settings, tutorial)
  Resources/                      asset catalog, string catalogs, sounds, privacy manifest
```

## Conventions

- **Bowl units.** Positions are in bowl units. The bowl's inner rim is the ellipse `(x / 0.75)² + (y / 1.0)² = 1`.
  `x` points to the right of the screen, `y` to the top of the screen (along the handle, away from the player). The
  physics position says how far the egg has rolled from the middle; it tips over the rim once it leaves the ellipse
  `(x / 0.57)² + (y / 0.76)² = 1` (`GameConfig.bowlRadiusX`, `bowlRadiusY`), and `EggPhysics.rimDistance` is its
  elliptical distance, 1 at the tipping point. The egg nearly fills the bowl, so the scene draws that position scaled
  down (`SceneLayout.eggOffset(for:)`).
- **Tilt.** Radians. `x > 0`: right edge down, the egg rolls right. `y > 0`: top edge down, the egg rolls up.
- **Light.** One key light for all artwork: from the **top right**, slightly in front of the viewer, like the owner's
  reference photo (`docs/reference-egg.jpg` is *not* committed; it was provided in the conversation). Shadows fall to
  the **bottom left**. Highlights sit on the upper right of convex shapes.
- **Determinism.** Anything all players must agree on (weather) derives from the race seed via `SplitMix64` and never
  from `random(in:)` or `Double.random`. Local randomness (footsteps, raindrops) uses a per-player seed.
- **Swift 6** language mode, strict concurrency. UI types are `@MainActor`; view models are `@Observable`.
  No force unwraps outside tests. No `print`; use `os.Logger` if logging is needed.
- **Strings.** German is the base language (du-form, generic masculine). UI code uses German literals
  (`Text("Spielen")`, `String(localized: "…")`), which the String Catalog translates to English. Every key needs an
  English translation in `App/Resources/Localizable.xcstrings`. Phones in any other language get English
  (`CFBundleDevelopmentRegion` is `en`).

## Screen composition (game)

Portrait, full screen, SpriteKit scene of the view's size (`resizeFill`, origin bottom left).

- **Background.** *Weiß*: warm off-white (#F7F6F3) with a barely visible radial vignette. *Kamera*: the scene is
  transparent and the rear camera preview sits behind the `SpriteView`.
- **Spoon.** Stainless-steel tablespoon from directly above, bowl centered horizontally with its center at 53 % of the
  screen height; the handle runs down past the bottom edge. One bowl unit is `u = min(0.3 · width, 0.145 · height)`
  points, so the bowl's inner rim is `1.5 u` wide and `2 u` tall and the spoon takes about half the screen's width.
  Bowl and egg stay clear of the HUD at the top and the sprint button at the bottom right, from an iPhone SE
  (375 × 667 pt) to a Pro Max (440 × 956 pt); `SceneLayoutTests` checks it.
- **Egg.** `1.44 u` wide and `1.9 u` tall, pointy end up: it nearly fills the bowl, so only the rolled lip and a few
  hundredths of a unit of the bowl show around it. It is too big to roll as far as the physics lets it, so
  `SceneLayout` scales its position per axis: at the tipping point it has ridden up onto the rim and hangs over the
  bowl's edge by a third of its half-width, its center still well inside the bowl, and it has grown by 5 %, closer to
  the eye. Its soft shadow falls towards the bottom left, `(−0.19, −0.09)` egg widths away (a bigger egg casts it
  further), onto the spoon and the white table; over the camera image it is cut to the spoon. It stretches as the egg
  climbs away from the center.
- **Spoon shadow.** Soft, on the white background only.
- **Tilt response.** The spoon stays fixed on screen (the phone is the spoon); its reflections shift slightly with the
  tilt and the egg rolls. No skewing of the spoon.
- **Drop.** The egg rolls on over the rim from where it is drawn. A tenth of a second later it is below the rim, so the
  spoon hides whatever part is still over the bowl. It falls on outwards, shrinking to 60 % as it falls away from the
  eye, until it clears the bowl's edge (`SceneLayout.landing(ofEggFallingFrom:)`), fades, and a broken egg (shell
  pieces, egg white, yolk; its image 1.4 times as wide as the egg) appears there, beside the spoon. A new egg is placed
  after two seconds. The `drop` preview sheet shows the fall frame by frame.
- **Weather overlays.** Rain: drops landing on the spoon and screen, streaks slanting with the wind, cooler and darker
  grading, wetter reflections. Wind: leaves and dust blowing across, wind arrow in the HUD. Gewitter: dark grading,
  warning flicker, bright flash. In camera mode the grading is a translucent overlay so it darkens the camera image.
- **HUD** (SwiftUI on top): meters, time, eggs left, weather icon with intensity and wind arrow, pause top right,
  sprint bottom right.

## EggscapeArt (texture contract)

Pure Swift, Foundation only, deterministic for a given input. Renders premultiplied **RGBA8 sRGB** pixel buffers, rows
top to bottom. The app turns them into `CGImage`/`SKTexture`; the `eggscape-art` tool writes them as PNG.

```swift
public struct PixelImage: Sendable, Equatable {
    public let width: Int
    public let height: Int
    public var rgba: [UInt8]   // premultiplied, width * height * 4 bytes
}

public enum EggArt {
    public static let aspect: Double                                   // height / width of the egg seen from above
    public static func egg(_ appearance: EggAppearance, width: Int) -> PixelImage      // no shadow, transparent
    public static func shadow(width: Int) -> PixelImage                               // soft, centered, egg-shaped
    public static func broken(_ appearance: EggAppearance, width: Int) -> PixelImage  // shell pieces, white, yolk
}

public enum SpoonArt {
    public struct Layout: Sendable, Equatable {
        public let width: Int, height: Int      // image size in pixels
        public let bowlCenterX: Double          // bowl center in pixels from the left
        public let bowlCenterY: Double          // bowl center in pixels from the top
        public let unit: Double                 // pixels per bowl unit
    }
    public static func layout(unit: Double) -> Layout
    public static func spoon(unit: Double) -> PixelImage       // the spoon, transparent background
    public static func shadow(unit: Double) -> PixelImage      // same size as spoon(), for the white background
    public static func highlight(unit: Double) -> PixelImage   // same size, additive reflections for tilt response
}

public enum EffectArt {
    public static func raindrop(diameter: Int, seed: UInt64) -> PixelImage   // a water drop lying on a surface
    public static func streak(length: Int) -> PixelImage                     // a falling rain streak
    public static func leaf(length: Int, seed: UInt64) -> PixelImage
    public static func splash(diameter: Int, seed: UInt64) -> PixelImage     // spray of droplets
}
```

`eggscape-art assets <Assets.xcassets>` (`make art`) writes the static textures (spoon layers) into image sets.
`eggscape-art preview <dir>` writes preview sheets. Egg skins are rendered at runtime, on a background task for the
shop, and cached on disk (`GameArtwork`); bump its `cacheVersion` when a renderer changes.

## Weather contract

`WeatherSchedule(seed:option:course:)` is the shared plan: stretches of weather along the track (`random` escalates,
Endlos intensifies every 100 m), a gust timeline and a lightning timeline in race time, and puddle positions. It is
identical for all players of a race. `WeatherSystem` applies it per player inside `RunEngine.step` and reports
`WeatherImpact` (force, damping scale, kicks) plus events (`weatherChanged`, `puddle`, `lightningWarning`,
`lightningStrike`). The HUD reads `RunEngine.weather.conditions` and the current wind.

## App flow

`AppServices` owns the long-lived objects (motion, settings, records, wallet, StoreKit, Game Center, camera, haptics,
sounds) and `GameLauncher`, which presents runs full screen above the tabs. A `RunSession` drives one run (calibration,
countdown, pause, results, rewards) around a `GameScene`, which steps the `RunEngine` at 120 Hz from
`SKScene.update(_:)`. `RunRules` say what a run counts towards (records, leaderboards, coins). Multiplayer races plug
into a run through `RaceHooks` (shared start instant, progress, drops, finish). `NearbySession` coordinates a nearby
room on top of `MultipeerTransport`; `GameKitTransport` carries the same messages over a Game Center match.
`--screenshot-mode <scene>` stages deterministic scenes for the App Store (`ScreenshotStage`). A staged run holds the
egg at a chosen physics position with feedback (`GameScene.holdEgg(at:)`), like a quick and attentive player, so it
keeps its eggs in any weather and after any retuning of `GameConfig`.

## Multiplayer contract

`Net/` defines `NetEnvelope { version, sender, message }` with `NetMessage` cases `lobbyState`, `setSettings`,
`ready`, `startRace(seed, startAt)`, `progress(meters, eggsLeft)` (10 Hz, unreliable), `eggDropped`, `finished`,
`results`, `ping`, `pong`, encoded as JSON. The host is the referee (`RaceReferee`): clock sync via ping/pong
(`ClockSync`), start time = host time + 3 s, finish order by arrival of `finished`. A `PeerTransport` protocol in the
app hides MultipeerConnectivity (Nearby) and GameKit (`GKMatch`, Online); `NearbyTransport` adds hosting, browsing
and joining for nearby rooms, so `NearbySession`'s join logic can be tested with a fake.

## Economy contract

`Economy/` holds the skin catalog (stable ids, `EggAppearance`, coin price), coin rewards for a finished run, the
coin pack product ids with their coin amounts, and a pure `Wallet` value (balance, owned skins, equipped skin).
The app persists the wallet in `UserDefaults` and credits StoreKit transactions exactly once (by transaction id).

## Leaderboards

Game Center leaderboards (configured in App Store Connect): best time per Zeitrennen distance (lower is better, in
hundredths of a second) and Endlos distance (meters, higher is better). IDs live in `Leaderboard/`.
