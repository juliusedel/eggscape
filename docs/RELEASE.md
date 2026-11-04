# Release

From this repository to Eggscape in the App Store, in the order the steps depend on each other. Steps marked
**Owner** need your Apple Account, your data, your money or your decision; **Repo** steps are commands in this
repository. Apple's pages are linked for the details; this page says what Eggscape needs from them.

Start steps 1 to 5 right away: enrollment, the name check, the website and the tax question can each take days, and
nothing in App Store Connect can begin before enrollment is through. Decisions that are still open are listed at the
end.

## 1. Join the Apple Developer Program (Owner)

Enroll as an individual at [developer.apple.com/programs/enroll][enroll] or in the Apple Developer app. You need the
Apple Account you use in Xcode, with two-factor authentication; the legal age of majority; your legal first and last
name in that account, because it becomes the seller name on the App Store; an address that is not a P.O. box; and your
own card. The fee is 99 USD per membership year, shown in local currency during enrollment. If no confirmation arrives
within 24 hours of the purchase, or the identity check stalls, contact Developer Support with your Enrollment ID
([enrollment help][enrollment]).

Without the paid membership there is no App Store Connect, TestFlight, Game Center or in-app purchase setup and no
upload; the free Personal Team only installs on your own devices ([compare memberships][memberships]).

## 2. Keep the bundle ID free (Owner)

Running the app on your iPhone with your Personal Team registers the App ID `de.juliusedel.eggscape` in that free team.
Apple engineers answer on the developer forums that it cannot be released by hand and that a paid team gets "not
available" until the free one lapses ([thread 843925][forum-app-id]); a Personal Team's App IDs expire 7 days after the
last build with it. So stop building with the Personal Team now. If the ID is still taken in step 11, wait a week or
ask Developer Support. The way out is a new bundle ID such as `de.juliusedel.eggscape.app` in project.yml (all three
targets) and fastlane/Appfile, chosen before the first upload, after which the bundle ID can never change. Product and
leaderboard IDs can stay.

## 3. Check the name (Owner)

An app record reserves its name, one app per name and localization ([add a new app][add-app]), and guideline
[2.3.7][guideline-2.3.7] asks for a unique one. An egg game called "Eggscape: Eier fangen" (English "Eggscape: Catch
the Eggs") has been on the German App Store since April 2026 ([App Store][other-eggscape]), and a US trademark filing
"EGGSCAPE" for game software exists, status unknown. Before step 12, search the [DPMA register][dpma],
[TMview][tmview] and the [USPTO][uspto] for "Eggscape" (classes 9 and 41). The name stays "Eggscape" unless that search
or legal advice says otherwise; a variant has at most 30 characters, such as "Eggscape: Eierlauf", and goes into
`fastlane/metadata/*/name.txt` and the display name (`CFBundleDisplayName` in App/Info.plist and
App/Resources/InfoPlist.xcstrings).

## 4. Publish the website (Owner)

App Store Connect needs a privacy policy URL and a support URL with real contact details, and selling coin packs from
Germany most likely needs an Impressum ([§ 5 DDG][ddg]). `site/` holds the pages, published with GitHub Pages:

| Page | URL |
|---|---|
| Datenschutzerklärung | https://juliusedel.github.io/eggscape/de/datenschutz/ |
| Support und Impressum | https://juliusedel.github.io/eggscape/de/support/ (Impressum: `#impressum`) |
| Privacy policy | https://juliusedel.github.io/eggscape/en/privacy/ |
| Support and legal notice | https://juliusedel.github.io/eggscape/en/support/ |

1. Replace every `TODO(owner)` in `site/` with your street address, postcode and town, email address and phone
   number, and in the privacy policy with the name and seat of your email provider; if it sits outside the EU and the
   EEA, add there on what basis the emails go to it, as section 10 does for GitHub. If you have a USt-IdNr. or a
   Wirtschafts-Identifikationsnummer (the BZSt assigns it without an application once the Finanzamt has you on record
   as economically active; ask in step 5), enter it in both Impressum sections in the row "USt-IdNr. / W-IdNr."
   ("VAT ID / Business ID" in English) and keep only the matching label; if you have neither, delete that row. The
   Steuernummer never goes there. All of this becomes public, like the trader details in step 9, so take an address
   you want to publish; a P.O. box does not do for the Impressum, a business address service may. Git keeps every
   committed version: an address or phone number you replace later stays readable in the public history of
   github.com/juliusedel/eggscape, even after the website shows the new one.
2. Have the privacy policy and the Impressum checked legally, by a lawyer or the IHK, before they go live.
3. `make site-check` lists the placeholders still left and checks the pages, the links and the page URLs in
   `fastlane/metadata`; it passes once none is left.
4. Once on GitHub, before the push with the filled-in pages: Settings → Pages → Build and deployment → Source:
   **GitHub Actions** ([GitHub docs][pages-source]); without it the workflow's deploy job fails. Then push to `main`.
   The Pages workflow publishes `site/` only once no placeholder is left; Actions → Pages → Run workflow starts it
   again by hand.

The app links the pages under Einstellungen → Hilfe & Rechtliches, and `fastlane/metadata/<language>/privacy_url.txt`
and `support_url.txt` hand them to App Store Connect with `make release`.

## 5. Ask about taxes in Germany (Owner)

Coin pack sales are income. Ask your Finanzamt or a tax advisor whether and how you register and pay tax on it in
Germany; that is separate from Apple's US tax form in step 8.

## 6. Set up the Mac (Owner, once)

- **Xcode 27.2** with the iOS 27.2 SDK builds and tests the app. App Store Connect accepts uploads built with Xcode 26
  or later, and from April 2027 only with the iOS 27 SDK or later ([upcoming requirements][upcoming],
  [news][sdk-27]).
- **Homebrew** from [brew.sh][homebrew], then:

  ```bash
  brew install xcodegen swiftformat fastlane   # without Homebrew: make bootstrap builds XcodeGen and SwiftFormat
  make gen && make test && make build
  ```

  fastlane needs Ruby 3.2 or later, newer than the Ruby that comes with macOS; Homebrew's fastlane brings its own
  ([fastlane setup][fastlane-setup]). With Ruby 3.2 or later from rbenv or mise, `bundle install` uses the Gemfile
  instead.
- **Without fastlane** you can still release: upload from Xcode's Organizer (step 20), capture screenshots with
  `make screenshots-sim` (step 22) and enter texts, URLs and screenshots in App Store Connect by hand. `make beta`,
  `make release` and `make screenshots` need fastlane.

## 7. Team ID and signing (Owner)

After enrollment, note the 10-character Team ID of the paid team (developer.apple.com → Account → Membership
details); it is not your Personal Team's. In Xcode → Settings → Accounts, stay signed in with that Apple Account: the
lanes let Xcode create the App Store signing profile through it (`-allowProvisioningUpdates`).

project.yml keeps its `<TEAM_ID>` placeholder. `make beta` and `make release` take the team from `EGGSCAPE_TEAM_ID`
(step 19) and hand it to the build. For a Run on your iPhone (step 20 needs one before the first archive) or an archive
in Xcode, pick the paid team under Signing & Capabilities. Every `make gen` resets that choice, and so does every
target that runs it first: `make build`, `make test`, `make test-app`, `make test-ui`, `make run`, `make strings`,
`make screenshots-sim` and the lanes behind `make beta`, `make release` and `make screenshots`. Pick the team again
before the next archive, or run those targets in a separate checkout such as a git worktree.

## 8. Agreements, bank account, tax form and DAC7 (Owner, Account Holder)

In App Store Connect → Business ([agreements][agreements]):

1. Accept the latest agreements; until then App Store Connect lets you add no app.
2. Paid Apps → **View and Agree to Terms**. Coin packs load only once this agreement is **Active**, also in the
   sandbox, in TestFlight and for App Review; before that the Münzen page says that coin packs are not available.
3. Enter the bank account, held in your legal name ([banking][banking]).
4. Tax Forms: the questionnaire picks Apple's US tax form; for an individual living in Germany it should be the
   **W-8BEN** ([tax information][tax]). If it offers W-9 or W-8BEN-E, check your answers or ask Apple before signing.
5. Agreements → Compliance → DAC7 → Add Info: **No**, the app offers no personal services ([DAC7][dac7]).

## 9. EU trader status (Owner, Account Holder)

Before the app reaches the EU, you declare whether you are a trader under the Digital Services Act: Business →
Agreements → Compliance → Digital Services Act → Complete Compliance Requirements ([DSA trader requirements][dsa]).
Apple names revenue from in-app purchases as a sign of being a trader, and declaring yourself no trader tells EU
customers that consumer rights do not apply to contracts with you.

As a trader you enter an address (or P.O. box), a phone number and an email address. Apple checks email and phone with
codes and the address with a document, and **publishes all three on the product page in all 27 EU countries**,
Germany included. Use the address of the Impressum (step 4) and a phone number that can receive codes, and start early:
the check can take a while. The setting for the app itself follows in step 13.

## 10. Small Business Program (Owner, optional)

In the [App Store Small Business Program][small-business], a new developer pays 15 % instead of 30 % commission on
in-app purchases. Joining needs the Account Holder and the accepted Paid Apps Agreement, and the lower rate starts 15
days after the end of the fiscal month in which Apple approves you, so apply before the first sales.

## 11. Register the App ID (Owner)

Certificates, Identifiers & Profiles → Identifiers → **+** → App IDs → App: explicit bundle ID
`de.juliusedel.eggscape` with the **Game Center** capability; In-App Purchase is on for every App ID
([register an App ID][app-id]). If it is "not available", see step 2.

## 12. Create the app record (Owner)

Apps → **+** → New App: platform iOS, name (step 3), primary language German, bundle ID `de.juliusedel.eggscape`,
SKU e.g. `eggscape` ([add a new app][add-app]). Do it soon, because the record reserves the name; if it is refused,
take a variant (step 3).

The primary language is the default for storefronts none of whose languages has its own texts, and you can change it
at any time ([App information][app-information]). `fastlane/metadata` has German and four English localizations
(en-US, en-GB, en-CA, en-AU), and every storefront lists German or one of these English variants
([App Store localizations][localizations]): the German texts appear where German is a storefront language (Germany,
Austria, Switzerland, Luxembourg), English texts everywhere else. `make release` adds the localizations that App Store
Connect does not have yet. Without fastlane, add them yourself: in the language menu at the top right of the app's
page, under Not Localized, pick English (U.S.), English (U.K.), English (Canada) and English (Australia) one after
another. A language you add shows the German screenshots until you upload its own (step 22).

## 13. App Information (Owner)

- Category **Games**, subcategories **Family** and **Sports** (also in `fastlane/metadata`).
- Content Rights: the app contains no third-party content.
- App Store Regulations and Permits → Digital Services Act: the trader status for this app (step 9).
- Digital Goods and Services in Your Apps, if the section is there: **Get Started** → Yes, customers can consume
  digital goods (the coin packs and the eggs they unlock) → **Apple In-App Purchase exclusively** for every country or
  region → check the Confirmation page → Save. The EU answers then stay locked for 12 months
  ([digital goods questionnaire][digital-goods]).

## 14. Age rating (Owner)

App Information → Age Rating opens Apple's current questionnaire ([values and definitions][age-ratings],
[set an age rating][set-age-rating]). Answer it honestly ([guideline 2.3.6][guideline-2.3.6]); it no longer asks about
in-app purchases. For Eggscape as it is:

- In-App Controls: no parental controls, no age assurance (unless the US decision below adds the Declared Age Range
  API).
- Capabilities: no unrestricted web access, no user-generated content, no social media, no messaging or chat, no
  advertising.
- Mature Themes, Medical or Wellness, Sexuality or Nudity, Violence: all **None**.
- Chance-Based Activities: Gambling **No**, Simulated Gambling **None**, Loot Boxes **No**. **Contests**, "events that
  allow users to compete with one another for rankings, rewards, or the achievement of personal goals", fit the races,
  best times, leaderboards and the coins for places in multiplayer races: **Infrequent** keeps 4+, **Frequent** gives
  13+. That answer is yours (open decisions); at 13+, read the store texts again for words aimed at children.
- From November 16, 2026 the questionnaire also asks about Shared Location and Dating and Relationships: **No** to both
  ([news][age-descriptors]).
- Made for Kids: no.

## 15. App Privacy (Owner)

- Privacy Policy URL: the pages from step 4 (`make release` sets them per language from `fastlane/metadata`).
- Data collection: **Data Not Collected**. The app has no server of its own, no analytics and no ads, and data that
  Apple collects for Game Center and purchases is not yours to disclose ([app privacy details][privacy-details]).
  Nearby sends the player name, egg and race data only to the other phones in the room, which keep nothing, so
  neither you nor a third-party partner can access it; online matching and leaderboards are Game Center, Apple's own
  service. That is why Apple's hint to declare Gameplay Content for multiplayer matching does not apply here. Change
  this answer before the app gets a server of its own, an SDK or analytics.

## 16. Pricing and Availability (Owner)

- Price: **free**; the app sells coin packs ([set a price][app-price]).
- Availability: every country or region except **China mainland**, where games need an NPPA approval number, and
  **Vietnam**, where they need a game license ([App information][app-information]). The United States depends on the
  open decision about age-signal laws.
- Untick "Make this app available on Apple Vision Pro", and under "iPhone and iPad Apps on Apple Silicon Mac" untick
  "Make this app available" if the section appears ([Vision Pro][vision-pro], [Mac][mac]). Neither a headset nor a Mac
  can be held like a spoon, and the `NO` settings in project.yml only change Xcode's run destinations, not App Store
  distribution.

## 17. The three coin packs (Owner)

Monetization → In-App Purchases → **+** → Consumable, three times, with exactly these product IDs: App Store
Connect never lets you change or reuse one ([In-App Purchase information][iap-information]).

| Product ID | Reference name | Price in Germany | Display name (de / en) |
|---|---|---|---|
| `de.juliusedel.eggscape.coins.small` | Coins small (600) | 0,99 € | Handvoll Münzen / Handful of Coins |
| `de.juliusedel.eggscape.coins.medium` | Coins medium (2000) | 2,99 € | Eierkarton voll Münzen / Egg Box of Coins |
| `de.juliusedel.eggscape.coins.large` | Coins large (5000) | 5,99 € | Hühnerstall voll Münzen / Henhouse of Coins |

- Price: Germany as the base country, from which Apple derives the other storefronts' prices
  ([set an In-App Purchase price][iap-price]). The amounts and the shop's "Bestes Angebot" badge are explained in
  `docs/ASSUMPTIONS.md`.
- Localizations: German, and the same English display name and description under English (U.S.), English (U.K.),
  English (Canada) and English (Australia), from `StoreKit/Eggscape.storekit`; they fit Apple's limits of 30 and 45
  characters. The storefront, not the phone's language, decides which language a pack's name shows in, and most
  storefronts list English only as English (U.K.), (Canada) or (Australia), so without those a pack may show its
  German name there. If you can, look at Shop → Münzen after the release on a phone whose App Store account is from
  the UK; the sandbox has been seen to show only a product's primary language, so TestFlight cannot prove it.
- App Review screenshot: Shop → Münzen with the three packs. The staged shop screenshot shows the egg page, so take
  it in the Simulator after a Run from Xcode, which uses the StoreKit configuration:
  `xcrun simctl io booted screenshot --type=jpeg coins.jpg`. It can be replaced later, not removed.
- The first consumables are reviewed only together with an app version: on each pack, **Add for Review** into the
  draft submission of version 1.0.0 (step 24, [submit an In-App Purchase][submit-iap]).

## 18. The four leaderboards (Owner)

In the app's Game Center section, create four **Classic** leaderboards. IDs, formats and sort orders must match
`Packages/EggscapeCore/Sources/EggscapeCore/Leaderboard/` ([leaderboard properties][leaderboards]):

| Leaderboard ID | Name (de / en) | Score format | Sort order |
|---|---|---|---|
| `de.juliusedel.eggscape.time.short` | Zeitrennen Kurz / Short Race | Elapsed time, 1/100 s | Low to High |
| `de.juliusedel.eggscape.time.medium` | Zeitrennen Mittel / Medium Race | Elapsed time, 1/100 s | Low to High |
| `de.juliusedel.eggscape.time.long` | Zeitrennen Lang / Long Race | Elapsed time, 1/100 s | Low to High |
| `de.juliusedel.eggscape.endless` | Endlos / Endless | Integer | High to Low |

- Each needs a reference name, which only you see, e.g. the English name. Descriptions and 1024 × 1024 images are
  optional.
- Score submission type: Best Score. The time trials use the elapsed-time format to the hundredth of a second; Endless
  gets " m" in both suffix fields, singular and plural, in every language.
- A leaderboard ID never changes, and a leaderboard cannot be deleted once it is live
  ([manage leaderboards][manage-leaderboards]).
- Like the coin packs, the first leaderboards are reviewed with an app version: tick **Game Center** on the version
  1.0.0 page and **Add for Review** each leaderboard into its draft submission (step 24,
  [submit Game Center components][submit-game-center]).

## 19. API key for fastlane (Owner, once)

Only needed for `make beta` and `make release` ([App Store Connect API][api]):

1. As Account Holder, once: Users and Access → Integrations → App Store Connect API → **Request Access**; Apple
   reviews the request.
2. Team Keys → Generate API Key with the access **App Manager**. Download the `.p8` file at once: it can be
   downloaded only once. Keep it outside the repository.
3. Export, e.g. in `~/.zprofile`:

   ```bash
   export ASC_KEY_ID=XXXXXXXXXX                                # Key ID in the Team Keys list
   export ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx   # Issuer ID above that list
   export ASC_KEY_PATH=$HOME/keys/AuthKey_XXXXXXXXXX.p8
   export EGGSCAPE_TEAM_ID=XXXXXXXXXX                          # Team ID of the paid team, step 7
   ```

   The lanes stop with a message when one is missing, or when `EGGSCAPE_TEAM_ID` is no 10-character Team ID.

## 20. Upload the first build (Owner)

Once, before the first archive, register your iPhone with the paid team: connect it, choose it as the run destination,
select the paid team under Signing & Capabilities and run the app (Product → Run, or Register Device if Xcode offers
it). Automatic signing signs an archive with a development profile first, and Xcode creates one only for a team with at
least one registered device. The iPhone you used with the Personal Team is not registered in the paid team. Without a
device, Product → Archive and `make beta` stop with "Your team has no devices from which to generate a provisioning
profile". Adding the iPhone's UDID under Certificates, Identifiers & Profiles → Devices works too.

In Xcode with the paid team selected and your iPhone registered with it: Product → Archive, then in the Organizer
**Validate App**, which checks signing, team, App ID and the app record before anything is uploaded, and **Distribute
App** → App Store Connect ([distributing your app][distribute]). Every upload needs a higher build number than the one
before; Xcode's distribution options can manage it ("Manage Version and Build Number").

Or **Repo**: `make beta` regenerates the project, sets the build number to the latest TestFlight build + 1 (only in
the generated project; App/Info.plist stays untouched), builds a signed Release archive with `EGGSCAPE_TEAM_ID` and
uploads it to TestFlight.

No export compliance question comes up: App/Info.plist already declares that the app uses no non-exempt encryption.

## 21. Test with TestFlight (Owner)

Once Paid Apps is Active and the packs and leaderboards exist ([in-app purchases in TestFlight][testflight-iap]):

- **Internal group:** add yourself; builds reach internal testers without a review ([internal testers][internal]).
- **External group** for friends: needs an internal group first, test information with a Beta App Description and a
  feedback email, and a TestFlight App Review of the first build ([external testers][external]).
- Purchases in TestFlight builds run in the sandbox and cost nothing. A Run from Xcode uses
  `StoreKit/Eggscape.storekit` and needs no account at all; to test a Run on a device against the App Store Connect
  products, set the Run scheme's StoreKit Configuration to None and sign in with a **Sandbox Apple Account** under
  Settings → Developer. Create it under Users and Access → Sandbox with an email address that was never an Apple
  Account, storefront Germany ([Sandbox Apple Account][sandbox]).
- Go through `docs/TESTING.md` on two iPhones, above all "In-app purchases" and "Game Center": a purchase interrupted
  by force-quitting the app, Ask to Buy, scores on all four leaderboards, an online race between two Game Center
  accounts and a nearby race. If you can, one iPhone runs iOS 17 or 18, because the app has only run on iOS 27 so far
  (open decisions). Check it once on an iPad too, where it runs in iPhone compatibility mode
  ([test compatible devices][compatible-devices]).

## 22. Screenshots (Owner, Repo)

App Store Connect requires at least one screenshot for **iPhone with Dynamic Island (medium display)**: 1206 × 2622,
e.g. iPhone 18 Pro. The pipeline also renders 1320 × 2868 (iPhone 18 Pro Max, large display). Each size takes up to 10
per language, and no image may have an alpha channel ([screenshot specifications][screenshot-specs]).

```bash
make screenshots-sim   # simctl only: no fastlane, no UI tests
make screenshots       # fastlane snapshot with the UI tests; the first run asks for your password (Automation Mode)
```

Both render the eight staged scenes (`--screenshot-mode`) in German and English on both simulators, one simulator at a
time, and save them as JPEG without alpha channel to `fastlane/screenshots/<language>/<simulator>-<nn>-<scene>.jpg`
(git-ignored). They copy en-US to en-GB, en-CA and en-AU and list every image with its size and alpha channel. Look at
each one; a scene that came out wrong, for example a run still showing its calibration card, can be captured again on
its own with `SCREENSHOT_SCENES=05-storm make screenshots-sim`.

The staged scenes use the white surface, because the Simulator has no camera. Add one or two photos of the camera
look, the default background, from a real iPhone in one of Apple's sizes: as JPEG
(`sips -s format jpeg IMG_0001.PNG --out 00-camera.jpg`) in `fastlane/screenshots/de-DE/` and `en-US/`, named so they
sort first, like `00-camera.jpg`. The pipelines replace only images named like their own output and copy the en-US
ones to the other English folders. With the eight scenes, two photos per size fit.

`make release` uploads everything and replaces the screenshots in App Store Connect for each language it has images
for, so anything added only in App Store Connect is gone after the next `make release`. Without fastlane, upload each
folder's JPEGs to its own language on the version page, in file-name order: `iPhone 18 Pro-*` under iPhone with
Dynamic Island (medium display), `iPhone 18 Pro Max-*` under the large display (View All Sizes in Media Manager).
en-GB, en-CA and en-AU get the copies in their own folders.

## 23. App Review information (Owner)

On the version page under App Review Information ([platform version information][version-information]):

- Contact: name, email address and phone number in international format (+49 …). Enter them in App Store Connect
  only: the repository is public, and `make release` leaves the contact as it is.
- Sign-in required: no, the app has no accounts.
- Notes: `fastlane/metadata/review_information/notes.txt` (English, within the 4000-byte limit) explains the run that
  moves by itself, finger steering in the Simulator, the camera prompt, the multiplayer modes that need a second
  device and why there is no Restore button. `make release` uploads it; otherwise paste it. A short video of a nearby
  and an online race on two phones, linked in the notes, helps the reviewer.

## 24. Submit version 1.0.0 (Owner)

1. `make release` uploads a new build with the texts, URLs, categories, review notes and screenshots; it never
   submits. Without fastlane, fill in all five languages by hand from `fastlane/metadata/<language>/`. `name.txt` and
   `subtitle.txt` go under App Information and `privacy_url.txt` under App Privacy (step 15). `description.txt`,
   `keywords.txt`, `promotional_text.txt`, `support_url.txt` and `marketing_url.txt` go on the version page, and
   `fastlane/metadata/copyright.txt` under Copyright. `release_notes.txt` waits for the first update, because the
   first version has no What's New field.
2. On the version page: without fastlane, first set the version number to 1.0.0, the build's version
   (`MARKETING_VERSION` in project.yml); App Store Connect names the first version 1.0, and `make release` renames it
   by itself. Then pick the build, check texts, screenshots and App Review Information, tick Game Center.
3. **Add for Review** on the version, then on each coin pack and each leaderboard into the same draft submission
   (steps 17 and 18): the first consumables and leaderboards are only reviewed together with an app version.
4. **Submit for Review** ([submit an app][submit-app]). App Review handles at least 50 % of submissions within 24 hours
   and 90 % within 48 hours ([App Review][app-review]).
5. `make release` sets the version to manual release: after approval, you release it.

## 25. After the release

- **Multiplayer Compatibility:** an update that keeps `EggscapeCore.protocolVersion` (now 3) can race against older
  versions; add Multiplayer Compatibility in its Game Center section, back to the earliest compatible version
  ([multiplayer compatibility][multiplayer]). A new protocol version gets no such entry.
- **iPhone Duo, April 2027:** submissions built with the iOS 27.1 SDK or later, as this project is, need iPhone Duo
  screenshots: outer display 1398 × 2034, inner display 2007 × 2853 ([screenshot specifications][screenshot-specs],
  [news][duo]). Unfold the iPhone Duo simulator and go through the app first; `xcrun simctl io <udid> enumerate` names
  the displays to capture. fastlane uploads them from 2.241.1 on.
- **iOS 27 SDK, April 2027:** uploads need the iOS 27 SDK or later; Xcode 27.2 already builds with it.
- **MultipeerConnectivity** is deprecated in the iOS 27 SDK. It still works; plan a Network framework transport
  behind `NearbyTransport` and keep Multipeer until the new one has raced on several phones ([TN3213][tn3213]).

## Open decisions

- **US storefront and age-signal laws.** Apple has applied Texas's SB 2420 to new Texas accounts since June 4, 2026
  ([news][texas]); similar duties follow in California (January 2027), Utah (May 2027) and Louisiana (July 2027).
  These laws make developers ask the app store for an age signal, which Apple provides through the Declared Age Range
  API; it needs iOS 26 or later and its own capability ([age assurance][age-assurance],
  [Declared Age Range][declared-age-range]). Either keep the US and have that built (a request at first launch behind
  `#available(iOS 26, *)`, the capability in App ID and entitlements, a sentence in the privacy policy, "Age
  Assurance" in the age rating), or leave the US out under Pricing and Availability until then. Decide with legal
  advice and check the dates again before the release.
- **iOS 17, 18 and 26.** The deployment target is iOS 17.0, but the app has only run on iOS 27. Either test it on iOS
  17, 18 and 26 (simulator runtimes from Xcode → Settings → Components, one at a time on a Mac with 8 GB, each with
  `make test-app`, `make test-ui` and a pass through the menus, a run, Einstellungen → Anleitung anzeigen and an
  invitation), or raise the minimum to the oldest version you tested, in project.yml and
  `Packages/EggscapeCore/Package.swift`. iOS 18 runs on the same iPhones as iOS 17.
- **Running or standing.** The store texts and the review notes say that the course runs by itself and you can play
  standing, and that whoever walks or runs along has to watch their surroundings. If players should really run, these
  texts change, and so does every hint about it in the app.
- **Contests in the age rating.** Infrequent (4+) or Frequent (13+), see step 14.
- **Primary language.** German for now. With the English localizations it only decides the default, and English would
  suit an app meant mostly for other countries. It can be changed at any time (step 12).

[add-app]: https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app
[age-assurance]: https://developer.apple.com/support/age-assurance/
[age-descriptors]: https://developer.apple.com/news/?id=yxkh08us
[age-ratings]: https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions
[agreements]: https://developer.apple.com/help/app-store-connect/manage-agreements/sign-and-update-agreements
[api]: https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api
[app-id]: https://developer.apple.com/help/account/identifiers/register-an-app-id
[app-information]: https://developer.apple.com/help/app-store-connect/reference/app-information/app-information
[app-price]: https://developer.apple.com/help/app-store-connect/manage-app-pricing/set-a-price
[app-review]: https://developer.apple.com/distribute/app-review/
[banking]: https://developer.apple.com/help/app-store-connect/manage-banking-information/enter-banking-information
[compatible-devices]: https://developer.apple.com/help/app-review/before-submitting-for-review/test-compatible-devices
[dac7]: https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-information-for-directive-on-administrative-cooperation-7th-amendment
[ddg]: https://www.gesetze-im-internet.de/ddg/__5.html
[declared-age-range]: https://developer.apple.com/documentation/declaredagerange
[digital-goods]: https://developer.apple.com/help/app-store-connect/manage-app-information/complete-the-digital-goods-and-services-questionnaire
[distribute]: https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases
[dpma]: https://register.dpma.de/
[dsa]: https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements
[duo]: https://developer.apple.com/news/?id=kkphp5qo
[enroll]: https://developer.apple.com/programs/enroll/
[enrollment]: https://developer.apple.com/support/enrollment/
[external]: https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers
[fastlane-setup]: https://docs.fastlane.tools/getting-started/ios/setup/
[forum-app-id]: https://developer.apple.com/forums/thread/843925
[guideline-2.3.6]: https://developer.apple.com/app-store/review/guidelines/#2.3.6
[guideline-2.3.7]: https://developer.apple.com/app-store/review/guidelines/#2.3.7
[homebrew]: https://brew.sh
[iap-information]: https://developer.apple.com/help/app-store-connect/reference/in-app-purchase-information
[iap-price]: https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/set-a-price-for-an-in-app-purchase
[internal]: https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers
[localizations]: https://developer.apple.com/help/app-store-connect/reference/app-information/app-store-localizations
[mac]: https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/manage-availability-of-iphone-and-ipad-apps-on-macs-with-apple-silicon
[manage-leaderboards]: https://developer.apple.com/help/app-store-connect/configure-game-center/manage-leaderboards
[leaderboards]: https://developer.apple.com/help/app-store-connect/reference/game-center/leaderboards
[memberships]: https://developer.apple.com/support/compare-memberships/
[multiplayer]: https://developer.apple.com/help/app-store-connect/configure-game-center/add-multiplayer-compatibility
[other-eggscape]: https://apps.apple.com/de/app/eggscape-eier-fangen/id6763054891
[pages-source]: https://docs.github.com/en/pages/getting-started-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site
[privacy-details]: https://developer.apple.com/app-store/app-privacy-details/
[sandbox]: https://developer.apple.com/help/app-store-connect/test-in-app-purchases/create-a-sandbox-apple-account
[screenshot-specs]: https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications
[sdk-27]: https://developer.apple.com/news/?id=k1mtkt1k
[set-age-rating]: https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating
[small-business]: https://developer.apple.com/app-store/small-business-program/
[submit-app]: https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app
[submit-game-center]: https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-game-center-components
[submit-iap]: https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase
[tax]: https://developer.apple.com/help/app-store-connect/manage-tax-information/provide-tax-information/
[testflight-iap]: https://developer.apple.com/help/app-store-connect/test-a-beta-version/testing-subscriptions-and-in-app-purchases-in-testflight/
[texas]: https://developer.apple.com/news/?id=sg176nne
[tmview]: https://www.tmdn.org/tmview/
[tn3213]: https://developer.apple.com/documentation/technotes/tn3213-moving-from-multipeer-connectivity-to-network-framework
[upcoming]: https://developer.apple.com/news/upcoming-requirements/
[uspto]: https://tmsearch.uspto.gov/
[version-information]: https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information
[vision-pro]: https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/manage-availability-of-iphone-and-ipad-apps-on-apple-vision-pro
