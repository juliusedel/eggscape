# Testing

## Automated

```bash
make test       # EggscapeCore (swift test) + app unit tests on an iPhone simulator
make test-ui    # UI tests: launch, and a complete 150 m time trial steered with a finger
```

CI (`.github/workflows/ci.yml`) runs `swift test` for EggscapeCore and an unsigned simulator build of the app.

UI tests need macOS **Automation Mode**. On a developer Mac the first `make test-ui` asks for your password in a
system dialog; to allow it permanently (e.g. on a build Mac) run once:

```bash
sudo automationmodetool enable-automationmode-without-authentication
```

The Simulator has no motion sensors, camera, haptics or Game Center account. There the game switches to finger
steering (drag the egg), the camera mode falls back to the white background, and Game Center shows "not available".
Everything below therefore has to be checked on real iPhones before a release.

## Manual device checklist

Use a release-like build (`make beta` → TestFlight, or Xcode → Product → Run with the Release configuration) on at
least one older (e.g. iPhone XR/11) and one current iPhone. Tick every line.

### Motion and calibration
- [ ] Calibrate holding the phone flat, then again tilted towards you (~40°): in both poses a level hold keeps the
      egg in the middle.
- [ ] Slowly tilting sideways drops the egg at roughly 14–15°, forwards/backwards at roughly 19–20°.
- [ ] A quick jerk drops it earlier (overshoot); small corrections feel forgiving.
- [ ] Empfindlichkeit 70 % vs 130 % makes a clear difference; the value survives an app restart.
- [ ] Pause → "Neu kalibrieren" works mid-run; Einstellungen → "Neu kalibrieren" stores a new level pose.
- [ ] The screen never dims during calibration, countdown or a run, and dims normally in the menus.

### Haptics and sound
- [ ] Light tick on every footstep, slightly stronger while sprinting.
- [ ] Continuous buzz that grows as the egg approaches the rim and stops when it is back in the middle.
- [ ] Sharp crack when the egg breaks; deep rumble on lightning.
- [ ] Einstellungen → Vibration off silences all of it.
- [ ] Sounds play; the ring/silent switch mutes them; music from another app keeps playing; "Ton" in the pause
      menu and in the settings mutes immediately.

### Camera mode
- [ ] Einstellungen → Hintergrund → Kamera asks for camera access once (German text in German, English in English).
- [ ] The live rear camera fills the screen behind the spoon, upright, with no visible lag.
- [ ] Declining access falls back to the white background and explains how to allow it.
- [ ] Rain and storm darken the camera image; the broken egg appears on the "ground".

### Weather
- [ ] Wind: gusts push the egg sideways, leaves blow across, the HUD arrow shows the direction.
- [ ] Regen: drops land on the spoon, the egg wobbles longer, puddles splash with an extra kick.
- [ ] Gewitter: a short warning flicker, then a bright flash, thunder and a strong push.
- [ ] Reduce Motion (iOS Settings → Accessibility) removes the camera shake.

### Modes and progress
- [ ] Zeitrennen Kurz/Mittel/Lang with each weather, personal bests appear in Einzelspieler and Bestenliste.
- [ ] Endlos: the weather gets rougher every 100 m; the record is kept.
- [ ] Gemeinsam an einem Handy: 2–4 players, pass-the-phone screens, final standings, "Nochmal".
- [ ] Coins are credited after runs; buying, equipping and seeing a new egg skin in the next run works.
- [ ] Einstellungen → Daten zurücksetzen clears settings, bests, coins and skins.

### In-app purchases (Sandbox account)
- [ ] The three coin packs load with localized prices.
- [ ] Buying a pack credits the coins exactly once, also after force-quitting the app during the purchase.
- [ ] "Ask to Buy" (Family Sharing child account) shows the pending state and credits after approval.

### Game Center
- [ ] Opening Bestenliste asks to sign in to Game Center (Apple's sheet) only then.
- [ ] After a finished time trial the score appears in the right leaderboard; Endlos submits meters.
- [ ] Global and friends scopes load; without Game Center the tab still shows personal bests.

### Nearby multiplayer (two or more phones)
- [ ] The Local Network prompt appears only when entering "In der Nähe", with the explanatory text.
- [ ] Raum erstellen on phone A, Beitreten on phone B: B sees A's nickname and joins; A accepts automatically.
- [ ] Lobby shows players, egg colors and ready states; only the host changes distance and weather.
- [ ] The 3-2-1 countdown starts at the same moment on all phones (film both screens to compare).
- [ ] During the race every phone shows all players' markers; egg drops show a toast on the other phones.
- [ ] Results list finish times and lost eggs; "Nochmal" returns to the lobby with the same players.
- [ ] Turning off Wi-Fi/Bluetooth on one phone mid-race marks it "Verbindung verloren"; the race continues.
- [ ] A fifth phone cannot join a full room.

### Lifecycle and power
- [ ] Going to the home screen or receiving a call pauses the run; coming back shows the pause menu.
- [ ] Low Power Mode: the game stays smooth (60 fps target) and haptics still work.
- [ ] A 10-minute endless run does not heat the phone noticeably or leak memory (Instruments → Allocations).

### Accessibility and localization
- [ ] VoiceOver reads every button in the menus and the HUD (pause, sprint, eggs left, weather).
- [ ] Dynamic Type at the largest size keeps the menus usable.
- [ ] German and English: no untranslated texts, no truncation (Settings → General → Language & Region).
- [ ] On an iPad the app runs in iPhone mode without crashing.
