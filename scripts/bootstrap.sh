#!/usr/bin/env bash
# Builds the pinned XcodeGen and SwiftFormat versions from source into .tools/bin.
# Only needed on Macs without Homebrew; `brew install xcodegen swiftformat` works just as well.
set -euo pipefail
cd "$(dirname "$0")/.."

XCODEGEN_VERSION="2.46.0"
SWIFTFORMAT_VERSION="0.64.4"
SRC=".tools/src"
mkdir -p .tools/bin "$SRC"

# build <name> <git url> <tag> <product>
build() {
    local name=$1 url=$2 tag=$3 product=$4
    if [[ ! -d "$SRC/$name" ]]; then
        git clone --quiet --depth 1 --branch "$tag" "$url" "$SRC/$name"
    fi
    swift build --package-path "$SRC/$name" -c release --product "$product"
    cp "$SRC/$name/.build/release/$product" .tools/bin/
}

build XcodeGen https://github.com/yonaskolb/XcodeGen.git "$XCODEGEN_VERSION" xcodegen
# XcodeGen loads its setting presets from this resource bundle next to the binary.
rm -rf .tools/bin/XcodeGen_XcodeGenKit.bundle
cp -R "$SRC/XcodeGen/.build/release/XcodeGen_XcodeGenKit.bundle" .tools/bin/

build SwiftFormat https://github.com/nicklockwood/SwiftFormat.git "$SWIFTFORMAT_VERSION" swiftformat

echo "xcodegen $(.tools/bin/xcodegen --version | sed 's/Version: //')"
echo "swiftformat $(.tools/bin/swiftformat --version)"
