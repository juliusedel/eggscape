#!/usr/bin/env bash
# iPhone simulator helper for the Makefile.
#   scripts/sim.sh udid   print the UDID of the simulator to use
#   scripts/sim.sh run    build Eggscape, boot the simulator and launch the app
# Set SIM_NAME (e.g. SIM_NAME="iPhone 17") to pick a specific device.
set -euo pipefail
cd "$(dirname "$0")/.."

BUNDLE_ID="de.juliusedel.eggscape"
DERIVED=".build/DerivedData"

udid() {
    local devices line=""
    devices=$(xcrun simctl list devices available)
    if [[ -n "${SIM_NAME:-}" ]]; then
        line=$(grep -E "^ +${SIM_NAME} \(" <<<"$devices" | tail -1 || true)
    else
        # A booted iPhone wins; otherwise the newest plain "iPhone NN" model.
        line=$(grep -E "^ +iPhone.*\(Booted\)" <<<"$devices" | head -1 || true)
        [[ -z "$line" ]] && line=$(grep -E "^ +iPhone [0-9]+ \(" <<<"$devices" | tail -1 || true)
        [[ -z "$line" ]] && line=$(grep -E "^ +iPhone" <<<"$devices" | tail -1 || true)
    fi
    if [[ -z "$line" ]]; then
        echo "No available iPhone simulator found (xcrun simctl list devices)." >&2
        exit 1
    fi
    sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/' <<<"$line"
}

run() {
    local id
    id=$(udid)
    xcodebuild -project Eggscape.xcodeproj -scheme Eggscape -derivedDataPath "$DERIVED" \
        -destination "id=$id" CODE_SIGNING_ALLOWED=NO -quiet build
    xcrun simctl boot "$id" 2>/dev/null || true
    # Bring up the Simulator window when the app is installed; headless setups work without it.
    open -b com.apple.iphonesimulator --args -CurrentDeviceUDID "$id" 2>/dev/null || true
    xcrun simctl install "$id" "$DERIVED/Build/Products/Debug-iphonesimulator/Eggscape.app"
    xcrun simctl launch "$id" "$BUNDLE_ID" "$@"
}

case "${1:-}" in
    udid) udid ;;
    run) shift; run "$@" ;;
    *) echo "usage: $0 udid|run [launch arguments]" >&2; exit 64 ;;
esac
