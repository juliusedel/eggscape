# Eggscape developer tasks. Run `make help` for an overview.
SHELL := /bin/bash
.SHELLFLAGS := -euo pipefail -c
.DEFAULT_GOAL := help

PROJECT := Eggscape.xcodeproj
SCHEME := Eggscape
CORE := Packages/EggscapeCore
DERIVED := .build/DerivedData

# Prefer tools on PATH (Homebrew); fall back to the copies scripts/bootstrap.sh builds into .tools/.
XCODEGEN := $(shell command -v xcodegen 2>/dev/null || echo .tools/bin/xcodegen)
SWIFTFORMAT := $(shell command -v swiftformat 2>/dev/null || echo .tools/bin/swiftformat)
FASTLANE := $(shell command -v fastlane 2>/dev/null || echo bundle exec fastlane)

# Simulator builds are unsigned so they work before a team is configured (see docs/RELEASE.md).
XCODEBUILD := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -derivedDataPath $(DERIVED) -quiet
SIM_FLAGS := CODE_SIGNING_ALLOWED=NO

.PHONY: help bootstrap gen build test test-core test-app test-ui run format lint strings icon sounds art beta release \
	screenshots screenshots-sim readme-images site-check clean

help: ## List the available targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-16s %s\n", $$1, $$2}'

bootstrap: ## Build XcodeGen and SwiftFormat from source into .tools/ (only needed without Homebrew)
	scripts/bootstrap.sh

gen: ## Generate Eggscape.xcodeproj from project.yml
	$(XCODEGEN) generate --quiet

build: gen ## Build the app for the iOS Simulator
	$(XCODEBUILD) -destination 'generic/platform=iOS Simulator' $(SIM_FLAGS) build

test: test-core test-app ## Run the EggscapeCore tests and the app unit tests

test-core: ## Run the EggscapeCore package tests on the Mac
	swift test --package-path $(CORE)

test-app: gen ## Run the app unit tests on an iPhone simulator
	$(XCODEBUILD) -destination "id=$$(scripts/sim.sh udid)" $(SIM_FLAGS) -only-testing:EggscapeTests test

test-ui: gen ## Run the UI tests on an iPhone simulator (a full race, takes a few minutes)
	$(XCODEBUILD) -destination "id=$$(scripts/sim.sh udid)" $(SIM_FLAGS) -only-testing:EggscapeUITests test

run: gen ## Build, install and launch the app on an iPhone simulator
	scripts/sim.sh run

# --config: inside a worktree under .claude/ SwiftFormat would also read the main checkout's config, which excludes it.
format: ## Format all Swift sources
	$(SWIFTFORMAT) --config .swiftformat .

lint: ## Check formatting without changing files
	$(SWIFTFORMAT) --config .swiftformat --lint .

strings: build ## Check that every UI string has an English translation
	swift scripts/check_strings.swift $(DERIVED) App/Resources/Localizable.xcstrings

art: ## Re-render the spoon images into the asset catalog (procedural, see EggscapeArt)
	swift run -c release --package-path $(CORE) eggscape-art assets App/Resources/Assets.xcassets

icon: ## Re-render the app icon from the game's spoon and egg (procedural, see EggscapeArt)
	swift run -c release --package-path $(CORE) eggscape-art icon App/Resources/Assets.xcassets/AppIcon.appiconset

sounds: ## Re-synthesize the sound effects
	swift scripts/make_sounds.swift App/Resources/Sounds

beta: ## Build and upload a TestFlight build (needs signing, see docs/RELEASE.md)
	$(FASTLANE) beta

release: ## Upload a build plus App Store metadata (see docs/RELEASE.md)
	$(FASTLANE) release

screenshots: ## Capture App Store screenshots with fastlane snapshot (UI tests, needs Automation Mode)
	$(FASTLANE) screenshots

screenshots-sim: gen ## Capture the same App Store screenshots with simctl, without fastlane or UI tests
	scripts/capture_screenshots.sh

readme-images: ## Render the icon, banner and phones of README.md from the English screenshots of screenshots-sim
	swift scripts/readme_images.swift

site-check: ## Check the support and privacy website in site/ before publishing it
	scripts/check_site.sh

clean: ## Remove build products and the generated project
	rm -rf .build $(PROJECT) $(CORE)/.build
