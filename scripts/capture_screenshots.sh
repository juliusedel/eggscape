#!/usr/bin/env bash
# Captures the App Store screenshots of the staged scenes (`--screenshot-mode`, App/Support/ScreenshotStage.swift)
# with simctl, without fastlane and without UI tests, which need macOS Automation Mode (docs/TESTING.md). `make
# screenshots-sim` runs it after `make gen`; `make screenshots` is the fastlane way to the same images.
#
# It builds the Debug app for the Simulator, then works through the simulators one at a time, because a Mac with 8 GB
# of memory runs one comfortably: boot, install, set the status bar to 9:41 with full battery and Wi-Fi, launch every
# scene in German and English, shut down. For each scene it waits until the app has drawn more than its launch screen
# (scripts/screen_drawn.swift), lets the scene settle and saves it as JPEG, which has no alpha channel (App Store
# Connect refuses one): fastlane/screenshots/<language>/<simulator>-<nn>-<scene>.jpg, the names `make screenshots`
# uses. A capture into which the Simulator drew the Dynamic Island, as it does now and then, is taken again. en-US is
# then copied to en-GB, en-CA and en-AU, the English localizations of the other storefronts.
#
# The captures wait in .build/screenshots until every scene worked, so a failed run leaves the previous set alone. A
# complete run then replaces every image named like its output, PNGs from `make screenshots` included; other images in
# fastlane/screenshots/<language>/, such as photos from a real iPhone, stay. en-GB, en-CA and en-AU are rebuilt from
# en-US every time, so English photos belong in en-US.
#
# Environment:
#   SCREENSHOT_DEVICES  simulators, comma-separated (default "iPhone 18 Pro Max,iPhone 18 Pro": the 6.9" size and the
#                       required 6.3" one). Without SCREENSHOT_SCENES the run is complete and also deletes the images
#                       of every simulator it does not list; to redo one size only, also set SCREENSHOT_SCENES to all
#                       eight scenes: 01-start,02-calibration,03-sunny,04-rain,05-storm,06-lobby,07-results,08-shop
#   SCREENSHOT_SCENES   only these scenes, comma-separated, e.g. "05-storm"; all other images stay as they are
set -euo pipefail
cd "$(dirname "$0")/.."

# The bundle ID of the app just built, read by build_app, so a new ID in project.yml needs no change here and a stale
# app with the old ID on the simulator is never launched instead.
BUNDLE_ID=""
DERIVED=".build/DerivedData"
APP="$DERIVED/Build/Products/Debug-iphonesimulator/Eggscape.app"
HELPER=".build/tools/screen_drawn"
OUTPUT="fastlane/screenshots"
WORK=".build/screenshots"

LANGUAGES=(de-DE en-US)
ENGLISH_COPIES=(en-GB en-CA en-AU)
# <file name> <scene> <seconds to settle once the app has drawn>, in App Store order. Names and order follow
# EggscapeUITests/ScreenshotTests.swift; the times were measured on an 8 GB Mac. A staged run opens on its moment of
# the race and stands still there (App/Support/ScreenshotStage.swift), so a late capture shows the same; it needs a few
# seconds for rain, drops and leaves to build up. The results appear 1.2 s after the finish it skips past.
SCENES=(
    "01-start start 1.5"
    "02-calibration calibration 2"
    "03-sunny run-sunny 5"
    "04-rain run-rain 5"
    "05-storm run-storm 5"
    "06-lobby lobby 2"
    "07-results results 9"
    "08-shop shop 2"
)
# Seconds the app gets to draw its first frame. A cold start of the Debug app took up to 15 s on an 8 GB Mac.
DRAW_TIMEOUT=60
# How often a capture showing the Dynamic Island is taken again, a second apart. It showed in about every fourth
# screenshot of a staged run, and right after a boot in up to seven in a row.
ISLAND_RETAKES=20
# What both screenshot pipelines write: "<simulator>-<nn>-<scene>.<png|jpg>", e.g. "iPhone 18 Pro-03-sunny.jpg".
GENERATED='^.+-[0-9]{2}-[a-z]+\.([Pp][Nn][Gg]|[Jj][Pp][Ee]?[Gg])$'
IMAGE='\.([Pp][Nn][Gg]|[Jj][Pp][Ee]?[Gg])$'
UDID='^[0-9A-F-]{36}$'

# The simulator that is booted while the script works with it, shut down again by `finish` if the script stops early.
CURRENT_UDID=""

fail() {
    echo "capture_screenshots: $*" >&2
    exit 1
}

# Prints $1 without the spaces around it.
trim() {
    local value=$1
    value=${value#"${value%%[![:space:]]*}"}
    printf '%s' "${value%"${value##*[![:space:]]}"}"
}

# Whether $1 is the file name of a scene, like "05-storm".
is_scene() {
    local entry name rest
    for entry in "${SCENES[@]}"; do
        read -r name rest <<<"$entry"
        if [[ $name == "$1" ]]; then
            return 0
        fi
    done
    return 1
}

# Whether scene $1 (a file name like "05-storm") is captured in this run.
is_selected() {
    [[ -z $SELECTED || $SELECTED == *",$1,"* ]]
}

# The UDID of the available simulator named exactly $1. simctl lists runtimes in ascending order, so the last match
# runs the newest one.
udid_for() {
    local line udid
    line=$(xcrun simctl list devices available | awk -v name="$1" '
        { entry = $0; sub(/^ +/, "", entry) }
        index(entry, name " (") == 1 { found = entry }
        END { print found }')
    udid=$(sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/' <<<"$line")
    [[ $udid =~ $UDID ]] || fail "no available simulator named \"$1\" (see xcrun simctl list devices available)"
    printf '%s\n' "$udid"
}

build_helper() {
    if [[ ! -x $HELPER || scripts/screen_drawn.swift -nt $HELPER ]]; then
        echo "Compiling scripts/screen_drawn.swift"
        mkdir -p "$(dirname "$HELPER")"
        xcrun --sdk macosx swiftc -O -o "$HELPER" scripts/screen_drawn.swift
    fi
}

# Builds the Debug app for the Simulator, unsigned like every simulator build here (see the Makefile).
build_app() {
    echo "Building the Debug app for the Simulator"
    xcodebuild -project Eggscape.xcodeproj -scheme Eggscape -configuration Debug -derivedDataPath "$DERIVED" \
        -destination "id=$1" CODE_SIGNING_ALLOWED=NO -quiet build
    [[ -d $APP ]] || fail "the build left no app at $APP"
    BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")
}

# The status bar fastlane snapshot sets with override_status_bar. An override sent while the simulator is still
# starting up can get lost, so every launch sends it again.
override_status_bar() {
    xcrun simctl status_bar "$1" override --time "9:41" --dataNetwork wifi --wifiMode active --wifiBars 3 \
        --cellularMode active --cellularBars 4 --operatorName "" --batteryState charged --batteryLevel 100
}

release_simulator() {
    xcrun simctl status_bar "$1" clear >/dev/null 2>&1 || true
    xcrun simctl shutdown "$1" >/dev/null 2>&1 || true
}

finish() {
    if [[ -n $CURRENT_UDID ]]; then
        release_simulator "$CURRENT_UDID"
    fi
}

# Saves what simulator $1 shows as JPEG at $2; simctl's own messages only matter when it fails.
screenshot() {
    local output
    if ! output=$(xcrun simctl io "$1" screenshot --type=jpeg "$2" 2>&1); then
        echo "$output" >&2
        return 1
    fi
}

# What scripts/screen_drawn.swift says about the screenshot $1: 0 drawn, 1 still flat, 2 drawn but with the Dynamic
# Island, 66 unreadable.
check_screen() {
    local status=0
    "$HELPER" "$1" >/dev/null || status=$?
    return "$status"
}

# Launches scene $5 on simulator $1 (named $2) in language $3 and saves it as $WORK/$3/$2-$4.jpg after $6 seconds of
# settling. The app counts as drawn when two screenshots a second apart show more than a flat color: right after the
# launch the home screen can still be visible, and it is not flat either. A screenshot from a real iPhone never shows
# the Dynamic Island, so a capture with the island in it is taken again a second later; the scenes stand still, so a
# later capture shows the same moment.
capture_scene() {
    local udid=$1 device=$2 language=$3 name=$4 scene=$5 settle=$6
    local probe="$WORK/probe.jpg" target="$WORK/$3/$2-$4.jpg"
    local attempt launched pid started hits status retakes
    for attempt in 1 2; do
        xcrun simctl terminate "$udid" "$BUNDLE_ID" >/dev/null 2>&1 || true
        sleep 1
        override_status_bar "$udid"
        launched=$(xcrun simctl launch "$udid" "$BUNDLE_ID" -AppleLanguages "($language)" \
            -AppleLocale "${language/-/_}" --screenshot-mode "$scene")
        pid=${launched##*: }
        [[ $pid =~ ^[0-9]+$ ]] || fail "unexpected answer from simctl launch: $launched"
        started=$SECONDS
        hits=0
        while ((hits < 2)); do
            sleep 1
            status=1
            if screenshot "$udid" "$probe" 2>/dev/null; then
                status=0
                check_screen "$probe" || status=$?
            fi
            # The app has drawn its screen, with the Dynamic Island or without.
            if ((status == 0 || status == 2)); then
                hits=$((hits + 1))
            else
                hits=0
                ((SECONDS - started < DRAW_TIMEOUT)) ||
                    fail "$device, $language, $name: the app drew nothing within ${DRAW_TIMEOUT} s"
            fi
        done
        sleep "$settle"
        retakes=0
        while true; do
            kill -0 "$pid" 2>/dev/null || fail "$device, $language, $name: the app quit before the capture"
            screenshot "$udid" "$target" || fail "$device, $language, $name: simctl could not take the screenshot"
            status=0
            check_screen "$target" || status=$?
            ((status == 2 && retakes < ISLAND_RETAKES)) || break
            retakes=$((retakes + 1))
            sleep 1
        done
        if ((status == 0)); then
            if ((retakes > 0)); then
                echo "  $language $name after $((SECONDS - started)) s, taken again $retakes x for the Dynamic Island"
            else
                echo "  $language $name after $((SECONDS - started)) s"
            fi
            return 0
        fi
        ((status != 2)) ||
            fail "$device, $language, $name: the Dynamic Island showed in $((ISLAND_RETAKES + 1)) captures in a row"
        echo "  $language $name showed the launch screen again (attempt $attempt)" >&2
    done
    fail "$device, $language, $name: every capture showed the launch screen"
}

# Captures the selected scenes in both languages on simulator $1 (named $2): boot, install, capture, shut down.
capture_device() {
    local udid=$1 device=$2 language entry name scene settle
    echo "$device ($udid)"
    CURRENT_UDID=$udid
    xcrun simctl bootstatus "$udid" -b >/dev/null
    xcrun simctl install "$udid" "$APP"
    for language in "${LANGUAGES[@]}"; do
        for entry in "${SCENES[@]}"; do
            read -r name scene settle <<<"$entry"
            if is_selected "$name"; then
                capture_scene "$udid" "$device" "$language" "$name" "$scene" "$settle"
            fi
        done
    done
    xcrun simctl terminate "$udid" "$BUNDLE_ID" >/dev/null 2>&1 || true
    release_simulator "$udid"
    CURRENT_UDID=""
}

# Moves the captures into fastlane/screenshots. A complete run first removes every image named like its output, which
# also drops PNGs from `make screenshots` and the images of simulators no longer listed; a run with SCREENSHOT_SCENES
# replaces only its own files, whatever their extension.
install_captures() {
    local language file base existing
    for language in "${LANGUAGES[@]}"; do
        mkdir -p "$OUTPUT/$language"
        for existing in "$OUTPUT/$language"/*; do
            base=$(basename "$existing")
            if [[ -f $existing && $base =~ $GENERATED ]]; then
                if [[ -z $SELECTED || -f "$WORK/$language/${base%.*}.jpg" ]]; then
                    rm -f -- "$existing"
                fi
            fi
        done
        for file in "$WORK/$language"/*.jpg; do
            mv -- "$file" "$OUTPUT/$language/"
        done
    done
}

# Gives en-GB, en-CA and en-AU the en-US images, photos from a real iPhone included: almost every App Store country
# lists English (U.K.), Canada and Australia also their own English, and the app has one English interface.
copy_english() {
    local language file
    for language in "${ENGLISH_COPIES[@]}"; do
        mkdir -p "$OUTPUT/$language"
        for file in "$OUTPUT/$language"/*; do
            if [[ -f $file && $file =~ $IMAGE ]]; then
                rm -f -- "$file"
            fi
        done
        for file in "$OUTPUT/en-US"/*; do
            if [[ -f $file && $file =~ $IMAGE ]]; then
                cp -p -- "$file" "$OUTPUT/$language/"
            fi
        done
    done
}

# Lists every image with its pixel size and alpha channel, and fails if one has an alpha channel.
summary() {
    local file info width height alpha with_alpha=""
    echo "Images in $OUTPUT:"
    while IFS= read -r -d '' file; do
        info=$(sips -g pixelWidth -g pixelHeight -g hasAlpha "$file")
        width=$(awk '/pixelWidth:/ { print $2 }' <<<"$info")
        height=$(awk '/pixelHeight:/ { print $2 }' <<<"$info")
        alpha=$(awk '/hasAlpha:/ { print $2 }' <<<"$info")
        printf '  %-44s %sx%s  hasAlpha: %s\n' "${file#"$OUTPUT"/}" "$width" "$height" "$alpha"
        if [[ $alpha != no ]]; then
            with_alpha+="  ${file#"$OUTPUT"/}"$'\n'
        fi
    done < <(find "$OUTPUT" -mindepth 2 -maxdepth 2 -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \) \
        -print0 | sort -z)
    [[ -z $with_alpha ]] || fail "App Store Connect refuses images with an alpha channel;" \
        "capture these again or save them as JPEG:"$'\n'"$with_alpha"
}

shopt -s nullglob
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

DEVICES=()
IFS=',' read -r -a entries <<<"${SCREENSHOT_DEVICES:-iPhone 18 Pro Max,iPhone 18 Pro}"
for entry in ${entries[@]+"${entries[@]}"}; do
    entry=$(trim "$entry")
    if [[ -n $entry ]]; then
        DEVICES+=("$entry")
    fi
done
((${#DEVICES[@]} > 0)) || fail "SCREENSHOT_DEVICES names no simulator"

# The selected scene names as ",05-storm,07-results,", empty for all of them.
SELECTED=""
if [[ -n ${SCREENSHOT_SCENES:-} ]]; then
    IFS=',' read -r -a entries <<<"$SCREENSHOT_SCENES"
    for entry in ${entries[@]+"${entries[@]}"}; do
        entry=$(trim "$entry")
        if [[ -n $entry ]]; then
            is_scene "$entry" || fail "SCREENSHOT_SCENES: no scene \"$entry\" (use the file names, 01-start to 08-shop)"
            SELECTED+=",$entry"
        fi
    done
    [[ -n $SELECTED ]] || fail "SCREENSHOT_SCENES names no scene"
    SELECTED+=","
fi

[[ -d Eggscape.xcodeproj ]] || fail "Eggscape.xcodeproj is missing; run make gen first (make screenshots-sim does)"
UDIDS=()
for device in "${DEVICES[@]}"; do
    udid=$(udid_for "$device")
    UDIDS+=("$udid")
done
running=$(xcrun simctl list devices booted | grep -c '(Booted)' || true)
if ((running > 0)); then
    echo "Note: $running simulator(s) already running; on a Mac with 8 GB, shut down the ones you do not need." >&2
fi

build_helper
build_app "${UDIDS[0]}"
rm -rf "$WORK"
for language in "${LANGUAGES[@]}"; do
    mkdir -p "$WORK/$language"
done
for index in "${!DEVICES[@]}"; do
    capture_device "${UDIDS[$index]}" "${DEVICES[$index]}"
done
install_captures
copy_english
summary
