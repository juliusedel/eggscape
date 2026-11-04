# Testing

## Automated

```bash
make test       # EggscapeCore (swift test) + app unit tests on an iPhone simulator
make test-ui    # UI tests: launch, the tutorial's name step, and a complete 15 m time trial steered with a finger
```

Launch arguments for tests and manual checks (`App/Support/LaunchOptions.swift`), all with fresh, throwaway data that
leaves the real data alone, without Game Center, and without picking up coin purchases that StoreKit still has to
deliver (the next normal launch credits them):

- `-ui-testing`: tutorial already seen, white background, fixed seeds.
- `-first-launch`: like a new install: the tutorial with its name step, the default settings (camera background),
  random seeds. Combined with `-ui-testing` only the seeds are fixed. `xcrun simctl launch <device>
  de.juliusedel.eggscape -first-launch` shows it in the Simulator.
- `--screenshot-mode <scene>`: the staged App Store scenes.

CI (`.github/workflows/ci.yml`) runs `swift test` for EggscapeCore and an unsigned simulator build of the app.

UI tests need macOS **Automation Mode**. On a developer Mac the first `make test-ui` asks for your password in a
system dialog; to allow it permanently (e.g. on a build Mac) run once:

```bash
sudo automationmodetool enable-automationmode-without-authentication
```

The Simulator has no motion sensors, camera, haptics or Game Center account. There the game switches to finger
steering (drag the egg), the camera mode (the default background) falls back to the white background without asking
for camera access, and Game Center shows "not available". UI tests and staged screenshots set the white background
themselves (`EggscapeApp.makeServices`).
Everything below therefore has to be checked on real iPhones before a release.

## Manual device checklist

Use a release-like build (`make beta` → TestFlight, or Xcode → Product → Run with the Release configuration) on at
least one older (e.g. iPhone XR/11) and one current iPhone. Tick every line.

### Motion and calibration
- [ ] Calibrate holding the phone flat, then again tilted towards you (~40°): in both poses a level hold keeps the
      egg in the middle.
- [ ] At Empfindlichkeit 100 %, slowly tilting the phone sideways drops the egg at roughly 5°, forwards/backwards
      at roughly 6.5° (a quick tilt a little earlier, about 4° and 5°): the base gain of 2.5 makes small turns of the
      wrist enough (`docs/TUNING.md`).
- [ ] A quick jerk drops it earlier (overshoot); small corrections feel forgiving.
- [ ] Empfindlichkeit 70 % vs 130 % makes a clear difference; the value survives an app restart. A value set in an
      earlier build stays where it was on the slider.
- [ ] Pause → "Neu kalibrieren" works mid-run; Einstellungen → "Neu kalibrieren" stores a new level pose.
- [ ] The safety note ("Die Strecke läuft von selbst …") is on the tutorial's first page, on the calibration screen
      and under the lobby's "Kalibrieren und bereit", in German and English, also at the largest text size.
- [ ] The screen never dims during calibration, countdown or a run, and dims normally in the menus.

### Haptics and sound
- [ ] Light tick on every footstep, slightly stronger while sprinting.
- [ ] Continuous buzz that grows as the egg approaches the rim and stops when it is back in the middle.
- [ ] Sharp crack when the egg breaks; deep rumble on lightning.
- [ ] Einstellungen → Vibration off silences all of it.
- [ ] Sounds play; the ring/silent switch mutes them; music from another app keeps playing; "Ton" in the pause
      menu and in the settings mutes immediately.

### Camera mode
- [ ] Fresh install (or Daten zurücksetzen with camera access never asked): Einstellungen → Hintergrund shows
      Kamera. The first single run or hot-seat run opens its calibration screen with "Gleich fragt iOS nach der
      Kamera", what the camera is for, and "Weiter" as its only button. "Weiter" brings up the prompt, whose text
      needs no "Kamera-Modus" to make sense (German text in German, English in English); a quick second tap brings
      up no second prompt. Allowing it goes on to the calibration with the camera behind it, now with "Abbrechen".
- [ ] Declining that prompt goes on to the calibration on the white background, without a black screen or an error,
      and switches Einstellungen → Hintergrund to Weiß.
- [ ] Choosing Kamera in Einstellungen after that keeps Kamera, and right under the picker a row says that runs are
      white without camera access, with "Einstellungen öffnen", which opens Eggscape's page in the iOS Settings.
- [ ] Allow the camera, then turn it off in the iOS Settings (Eggscape → Kamera): runs show white, Einstellungen still
      shows Kamera and the same row under the picker. Allowing it again there brings the camera back, and the row goes.
- [ ] After declining the camera, Einstellungen → Daten zurücksetzen leaves Hintergrund on Weiß (iOS keeps the "no");
      with camera access allowed or never asked it shows Kamera.
- [ ] A fresh install whose first run is a nearby or online race shows no prompt during the countdown (the race runs
      on white); the next single run shows the camera note first.
- [ ] A background chosen in an earlier build is kept after the update (Weiß stays Weiß).
- [ ] Einstellungen → Hintergrund → Kamera asks for camera access once if it was never asked; declining it there
      switches back to Weiß without a further message.
- [ ] The live rear camera fills the screen behind the spoon, upright, with no visible lag.
- [ ] Rain and storm darken the camera image; the broken egg appears on the "ground".

### Weather
- [ ] Wind: gusts push the egg sideways, leaves blow across, the HUD arrow shows the direction.
- [ ] Regen: drops land on the spoon, the egg wobbles longer, puddles splash with an extra kick (on 100 m: one to
      three puddles, the first 25–60 m from the start; on 50 m only about seven races in ten have one, on 15 m none).
- [ ] Gewitter: a short warning flicker, then a bright flash, thunder and a strong push (on 50 or 100 m: the first
      strike comes 8 s or more after the start, when a clean 15 m run is over).
- [ ] Dim Flashing Lights (iOS Settings → Accessibility → Motion): in a Gewitter the picture brightens slowly a moment
      before a strike instead of flickering, and the strike only lightens it to about a third and fades slowly; thunder
      and push stay. Turned on during a paused run, it applies from the next run.
- [ ] Reduce Motion (iOS Settings → Accessibility → Motion) removes the camera shake, and the countdown's numbers and
      "Los!" fade in and out without zooming or bouncing.

### Modes and progress
- [ ] Zeitrennen Kurz/Mittel/Lang with each weather, personal bests appear in Einzelspieler and Bestenliste.
- [ ] Updating from a build with the 150 / 300 / 600 m courses: the old best times are gone ("Noch keine"), the
      Endlos record is still there.
- [ ] Endlos: the weather gets rougher every 100 m; the record is kept.
- [ ] Gemeinsam an einem Handy: 2–4 players, pass-the-phone screens, final standings, "Nochmal".
- [ ] An einem Handy with four named players: type in the third row, swipe it away while the keyboard is up, then
      delete the second and start: no crash, the deleted row slides out (not the last one), the other names stay in
      their rows and the race hands the phone to them in that order. With two players no row offers a delete.
- [ ] Coins are credited after runs; unlocking, equipping and seeing a new egg skin in the next run works. A clean
      run in calm weather that sets no new best shows "+8 Münzen" over 15 m, "+28" over 50 m and "+55" over 100 m.
- [ ] Einstellungen → Daten zurücksetzen clears settings, bests, coins and skins; its footer and its question say
      that bought coins go too.

### Shop
- [ ] On fresh data (or after Daten zurücksetzen) only Klassisch Weiß is unlocked; every other egg shows a padlock
      in front of it and its price, cheapest first. "1 von 20 Eiern freigeschaltet" sits above the grid.
- [ ] After the first clean 100 m run in calm weather (55 coins, plus 20 for the first personal best: 75) the
      padlocks and prices of Hofei Braun (55) and Wachtelei (70) turn orange; the eggs that still cost more keep a
      frosted padlock and a grey price. (A first clean run pays 11 coins over 15 m and 38 over 50 m, not enough for
      any egg yet.)
- [ ] Tapping an orange (affordable) egg asks "Ei freischalten?" with its name and price. Confirming takes exactly
      that many coins, the padlock disappears, the egg is put on (orange border, "Ausgewählt"), the coin sound
      plays and, with Vibration on, a short success vibration follows. "Abbrechen" changes nothing.
- [ ] Tapping a grey (too expensive) egg says how many coins are missing. "Münzen kaufen" opens the Münzen page at
      its top, also when the egg was at the bottom of the grid; "Abbrechen" stays on the Eier page.
- [ ] Tapping an unlocked egg puts it on without asking; the next run shows it in the spoon.
- [ ] Tapping the coin balance (with the plus) on the Eier page opens the Münzen page; the picker switches back.
- [ ] The Münzen page says under the packs that coins, bought ones too, are stored only on this device.
- [ ] VoiceOver on an egg: name, then "Gesperrt" and its price, then "Schaltet das Ei frei." or how many coins are
      missing; unlocked eggs say "Freigeschaltet", the egg in use is announced as selected. The balance says what it
      opens; every coin pack reads its name, price, coins and, on one of them, "bestes Angebot".
- [ ] Largest Dynamic Type size: names, prices and the coin cards stay readable, the padlocks stay on the eggs.

### In-app purchases
Locally, run from Xcode: the Run scheme uses `StoreKit/Eggscape.storekit`, no Apple account needed and no paid
developer program. `make test-app` loads the packs from the same file and buys one in a StoreKitTest session
(`StoreServiceTests`). Notes for running from Xcode:

- It works without the debugger (the Run scheme leaves "Debug executable" off): Xcode syncs the configuration to the
  Simulator or iPhone as part of the run (the run's log in the Report navigator lists a "StoreKitTesting" step,
  "StoreKit Configuration sync"), and StoreKit keeps it for the app.
- The sync needs a run that launched. A run that failed to launch (Developer Mode off, developer certificate not yet
  trusted in Settings → General → VPN & Device Management) synced nothing, and opening the app from the Home Screen
  then asks the real App Store, which has no packs for this app yet: the Münzen page says they are not available.
  Run it from Xcode again once the device is set up.
- If the page says so anyway, check Edit Scheme → Run → Options → StoreKit Configuration ("Eggscape.storekit") and
  tap "Erneut versuchen".
- Real purchases always use the Apple Account the device uses for the App Store (a Sandbox Apple Account for
  testing); the app has no sign-in of its own. StoreKit testing in Xcode needs no account at all.

- [ ] Shop → Münzen lists the three packs as cards with 0,99 € / 2,99 € / 5,99 € (German storefront of the
      configuration); the 5.000 pack carries "Bestes Angebot".
- [ ] Buying a pack credits its coins exactly once (the balance counts up); Debug → StoreKit → Manage Transactions
      lists the transaction as finished.
- [ ] With Ask to Buy enabled in the StoreKit configuration (open `StoreKit/Eggscape.storekit`, Editor menu), buying
      says once "Kauf ausstehend"; approving it in Manage Transactions credits the coins. With failing transactions
      enabled there, buying shows "Kauf nicht möglich" and credits nothing.
- [ ] Without a StoreKit configuration (Run scheme → Options → StoreKit Configuration: None) the Münzen page says
      that coin packs are not available right now and offers "Erneut versuchen"; the Eier page keeps working.

On a device with a **Sandbox Apple Account** (Settings → Developer):
- [ ] The three coin packs load with localized prices.
- [ ] Buying shows the App Store's sheet over the app (the shop buys through SwiftUI's purchase action), with
      TestFlight on iOS 17 or 18 as well if a device has it; iOS 18.2 was reported to fail `Product.purchase()` without
      a scene.
- [ ] Buying a pack credits the coins exactly once, also after force-quitting the app during the purchase.
- [ ] "Ask to Buy" (Family Sharing child account) says once that the purchase waits for approval, and credits the
      coins after approval; cancelling the App Store sheet shows no message.

### Game Center
- [ ] Signed in to Game Center: launching the app signs in silently, without a sheet.
- [ ] Signed out: no sheet at launch or during a run; Apple's sign-in sheet appears when Bestenliste or Online opens.
- [ ] Accept a friend's Online invitation while the app is not running: the app opens straight into the online room
      (after the tutorial on a first launch).
- [ ] After a finished time trial the score appears in the right leaderboard; Endlos submits meters.
- [ ] Global and friends scopes load; without Game Center the tab still shows personal bests.

### Nearby multiplayer (two or more phones)
Use two real iPhones. MultipeerConnectivity between the Simulator and an iPhone is unreliable: the Simulator has no
Bluetooth or peer-to-peer Wi-Fi, only the Mac's network, so a room can be listed while joining it fails. If you try it
anyway, both must be on the same Wi-Fi without client isolation or VPN, and the Mac must let the Simulator use the
local network (System Settings → Privacy & Security → Local Network, and the firewall).

Why a join failed is logged (subsystem `de.juliusedel.eggscape`, category `nearby`): the joiner logs the reason and how
many seconds it took, the host why it turned an invitation down or could not seat a phone that had connected. When
iOS turns down advertising the room or looking for rooms, the phone logs "Could not advertise the room" or "Could not
look for rooms" with the error, and when it tries again. Read it in Xcode's console (it shows the app's log also
without the debugger, which the Run scheme leaves off), in Console.app with the iPhone selected, or for the Simulator
with `xcrun simctl spawn booted log stream --level info --predicate 'subsystem == "de.juliusedel.eggscape"'`.

- [ ] The Local Network prompt appears only once Raum erstellen or Beitreten is tapped, with the explanatory text.
- [ ] Two fresh installs that both see the prompt for the first time (the App Review setup): Raum erstellen on A,
      Beitreten on B, "Erlauben" on both. B lists A's room within a few seconds, without leaving the screen. iOS may
      turn down the first search while its prompt is up; the app looks again once it is active.
- [ ] Host alone in its room: below the host, "Warte auf Mitspieler …" and "Auf den anderen Handys: Mehrspieler →
      In der Nähe → Beitreten."; after about 10 s alone, a hint on "Lokales Netzwerk" with "Einstellungen öffnen",
      which opens Eggscape's page in the iOS Settings. Both go once a player joins.
- [ ] Joiner with no room for about 10 s (no host yet): the room list adds the hint on "Lokales Netzwerk" with
      "Einstellungen öffnen"; it goes as soon as a room is listed.
- [ ] "Nicht erlauben" on one phone: neither phone sees the other, and both show the hint after about 10 s. Allowing
      "Lokales Netzwerk" in the settings and coming back to the app brings the room up, without leaving the screen.
- [ ] Raum erstellen on phone A, Beitreten on phone B: B sees A's nickname and joins; A accepts automatically.
- [ ] Lobby shows players, egg colors and ready states; only the host changes distance and weather.
- [ ] The 3-2-1 countdown starts at the same moment on all phones (film both screens to compare).
- [ ] During the race every phone shows all players' markers; egg drops show a toast on the other phones.
- [ ] Results list finish times and lost eggs; "Nochmal" returns to the lobby with the same players.
- [ ] Turning off Wi-Fi/Bluetooth on one phone mid-race marks it "Verbindung verloren"; the race continues.
- [ ] A fifth phone cannot join a full room: the host stops listing it, and a phone that still lists it, or asks
      for the last seat at the same moment as another phone, reads "Beitreten hat nicht geklappt …". "Der Raum ist
      voll." is only a fallback for a lobby that has no seat once the joiner has connected; it should not normally
      appear.
- [ ] A join that does not work out (e.g. the host leaves while the joiner shows "Verbinde …") returns to the room
      list with "Beitreten hat nicht geklappt …", which names the possible reasons and what helps; it never waits on
      "Verbinde …" for more than about half a minute, and joining again from the list works.

### Lifecycle and power
- [ ] Going to the home screen or receiving a call pauses the run; coming back shows the pause menu.
- [ ] Low Power Mode: the game stays smooth (60 fps target) and haptics still work.
- [ ] A 10-minute endless run does not heat the phone noticeably or leak memory (Instruments → Allocations).

### Tutorial
- [ ] First launch (or `-first-launch`): the tutorial opens; "Überspringen" is a clearly visible button of at least a
      finger's size in its own bar above the pages, also at the largest Dynamic Type size, and never covers a page's
      text.
- [ ] "Überspringen" on any of the three pages, and "Weiter" on the third, lead to "Wie heißt du?"; that step has no
      "Überspringen".
- [ ] On a first launch the keyboard comes up by itself; the field, the hint under it and "Los geht’s" stay above the
      keyboard on the smallest iPhone and at the largest text size (the text above them scrolls).
- [ ] "Los geht’s" or the keyboard's Return key stores the name without leading or trailing spaces; Mehrspieler →
      In der Nähe says "Du spielst als …" with it, and An einem Handy fills it in for Spieler 1. An empty name stays
      allowed and shows as "Spieler".
- [ ] Einstellungen → "Anleitung anzeigen" shows the tutorial again with the current name filled in (no keyboard);
      "Los geht’s" keeps or changes it.
- [ ] An online invitation accepted during the tutorial waits until it is finished.

### Accessibility and localization
- [ ] VoiceOver reads every button in the menus and the HUD (pause, sprint, eggs left, weather).
- [ ] Dynamic Type at the largest size keeps the menus usable.
- [ ] German and English: no untranslated texts, no truncation (Settings → General → Language & Region).
- [ ] A phone whose languages include neither German nor English (e.g. only French) shows the app, the camera
      and local network prompts and the help pages in English; a German phone shows the prompts in German.
- [ ] Einstellungen → Hilfe & Rechtliches: "Datenschutz" and "Support & Impressum" open the German pages in Safari
      when the app runs in German, the English pages otherwise; "Version" shows the version and build.
- [ ] On an iPad the app runs in iPhone mode without crashing.

### Waiting in rooms and invitations
- [ ] Nearby and online: the phone that finishes first does not dim or lock while "Warte auf die anderen …", the
      results or the lobby are shown (wait longer than Auto-Lock); after leaving the room it dims normally again.
- [ ] Host (nearby) or referee (online): Pause → "Rennen verlassen" warns that the race ends for the others too; every
      other player reads that the others keep running.
- [ ] Accept an online invitation during a single run or a hot-seat turn: it waits until the run and its results are
      closed, then opens, never on top of them. During a nearby or online race it waits for the race to end; back in
      the room, "Einladung annehmen?" asks first.
- [ ] Accept one while in a nearby lobby or an online room: "Einladung annehmen?" asks first; "Annehmen" leaves the
      room and opens the invitation, "Ablehnen" stays.
- [ ] A joiner who leaves "Einladung annehmen?" open still gets the race screen when the host starts; after the race
      the question appears again in the lobby.
- [ ] Host taps "Nochmal" with an invitation pending: the results close and the question appears.
- [ ] Signed out of Game Center: right after launching the app, open Bestenliste and switch to Einzelspieler before
      anything appears, then start a run. Apple's sign-in sheet never appears over the run; it appears on the next
      visit to Bestenliste.
- [ ] Disabled primary buttons (e.g. "Rennen starten" before everybody is ready) and the Sprint button stay readable
      in light and dark mode.
