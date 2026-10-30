# Release

From a fresh checkout to an app in review. Steps marked **Owner** need your Apple account and cannot be automated.

## 1. Tools

```bash
brew install xcodegen swiftformat fastlane   # or: make bootstrap (XcodeGen + SwiftFormat from source)
make gen && make test && make build
```

Xcode 26 or later is required (the app uses the iOS 26 Liquid Glass styles when available; it still runs on iOS 17).

## 2. Apple Developer account (Owner)

1. Note your **Team ID** (developer.apple.com → Membership). Replace `<TEAM_ID>` in `project.yml`, then `make gen`.
2. Certificates, Identifiers & Profiles → Identifiers: register the App ID **de.juliusedel.eggscape** with the
   **Game Center** capability (In-App Purchase is enabled for every App ID). Automatic signing creates the
   profiles when you build with `-allowProvisioningUpdates` (the fastlane lanes do).

## 3. App Store Connect app record (Owner)

1. My Apps → **+** → New App: platform iOS, name **Eggscape**, primary language **German**, bundle ID
   **de.juliusedel.eggscape**, SKU e.g. `eggscape`.
2. **App Information:** category **Games**, subcategories **Family** and **Sports**; content rights: no third-party
   content.
3. **Age Rating:** answer "None" to every content question and "No" to unrestricted web access, user-generated
   content, messaging, gambling and advertising; In-App Purchases: **Yes**. The result must be **4+**.
4. **App Privacy:** privacy policy URL (required, e.g. a GitHub Pages page saying that Eggscape collects no data,
   that the camera image is only shown on screen, and that Game Center and in-app purchases are handled by Apple).
   Data collection: **"Data Not Collected"**.
5. **Pricing:** free (the app sells consumable coin packs).
6. Support URL and marketing URL in the version page (`fastlane/metadata/*/` holds the texts; add
   `support_url.txt` and `privacy_url.txt` there if you want fastlane to upload them).

## 4. In-app purchases (Owner)

1. Business → **Paid Apps Agreement**: accept it and fill in bank and tax information. Without it, products never
   load (the shop then shows that coin packs are unavailable, the rest of the game works).
2. App → Monetization → In-App Purchases → **+ Consumable**, three times:

   | Product ID                              | Reference name    | Coins | Suggested price |
   |-----------------------------------------|-------------------|-------|-----------------|
   | `de.juliusedel.eggscape.coins.small`    | Coins small       | 600   | 0,99 €          |
   | `de.juliusedel.eggscape.coins.medium`   | Coins medium      | 2000  | 2,99 €          |
   | `de.juliusedel.eggscape.coins.large`    | Coins large       | 5000  | 5,99 €          |

   The amounts are sized against the egg prices (see `docs/ASSUMPTIONS.md`): the small pack buys any common egg, the
   medium one any rare egg, the large one any egg but the last. The shop's "Bestes Angebot" badge follows the prices:
   it marks whichever pack gives the most coins for the money in the player's storefront (at the suggested prices,
   the large one).

   Add German and English display names/descriptions (see `StoreKit/Eggscape.storekit`) and a review screenshot of
   the coin shop (Shop → Münzen) for each product. Submit them together with the first app version.
3. For local testing, a Run from Xcode uses `StoreKit/Eggscape.storekit` (Run scheme) on the Simulator and on a
   device, with no Apple Account and no paid program (see `docs/TESTING.md`). To test against the products in App
   Store Connect instead (Run scheme → Options → StoreKit Configuration: None), sign in to a **Sandbox Apple Account**
   under Settings → Developer.

## 5. Game Center leaderboards (Owner)

App → Services → Game Center: enable Game Center and create four **Classic leaderboards**:

| Leaderboard ID                           | Name (de / en)                  | Score format              | Sort      |
|------------------------------------------|---------------------------------|---------------------------|-----------|
| `de.juliusedel.eggscape.time.short`      | Zeitrennen Kurz / Short Race    | Elapsed time, hundredths  | Low → high |
| `de.juliusedel.eggscape.time.medium`     | Zeitrennen Mittel / Medium Race | Elapsed time, hundredths  | Low → high |
| `de.juliusedel.eggscape.time.long`       | Zeitrennen Lang / Long Race     | Elapsed time, hundredths  | Low → high |
| `de.juliusedel.eggscape.endless`         | Endlos / Endless                | Integer, suffix " m"      | High → low |

Score submission type: best score. Add them to the app version before submitting.

## 6. App Store Connect API key (Owner, once)

Users and Access → Integrations → App Store Connect API → **+**, role **App Manager**. Download the `.p8` file and
export:

```bash
export ASC_KEY_ID=XXXXXXXXXX
export ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
export ASC_KEY_PATH=$HOME/keys/AuthKey_XXXXXXXXXX.p8
export EGGSCAPE_TEAM_ID=YOURTEAMID
```

## 7. TestFlight

```bash
make beta
```

Regenerates the project, sets the build number to the latest TestFlight build + 1 (agvtool), builds a signed Release
archive and uploads it. In App Store Connect → TestFlight answer the export compliance question (already declared in
Info.plist: no non-exempt encryption) and add testers. Run `docs/TESTING.md` on real devices.

## 8. Screenshots

```bash
make screenshots
```

Renders the staged scenes (`--screenshot-mode`) in German and English on the 6.9" iPhone simulator into
`fastlane/screenshots/` (git-ignored). Check them, then upload with `make release` (or drag them into App Store
Connect).

## 9. Submit

```bash
make release
```

Uploads a new build plus metadata and screenshots; it does **not** submit. In App Store Connect (Owner): pick the
build, attach the three in-app purchases and the four leaderboards to the version, add review notes ("Tilt the phone
to keep the egg on the spoon; in the Simulator you can drag the egg with a finger. Eggs are unlocked with coins
earned by playing; coin packs (Shop → Münzen) are consumables. No login required."), then **Submit for Review**.
