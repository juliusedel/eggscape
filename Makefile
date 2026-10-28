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

.PHONY: help bootstrap gen build test test-core test-app test-ui run format lint icon sounds beta release screenshots clean

help: ## List the available targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-12s %s\n", $$1, $$2}'

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

format: ## Format all Swift sources
	$(SWIFTFORMAT) .

lint: ## Check formatting without changing files
	$(SWIFTFORMAT) --lint .

icon: ## Regenerate the app icon
	swift scripts/make_icon.swift App/Resources/Assets.xcassets/AppIcon.appiconset

sounds: ## Re-synthesize the sound effects
	swift scripts/make_sounds.swift App/Resources/Sounds

beta: ## Build and upload a TestFlight build (needs signing, see docs/RELEASE.md)
	$(FASTLANE) beta

release: ## Upload a build plus App Store metadata (see docs/RELEASE.md)
	$(FASTLANE) release

screenshots: ## Capture App Store screenshots with fastlane snapshot
	$(FASTLANE) screenshots

clean: ## Remove build products and the generated project
	rm -rf .build $(PROJECT) $(CORE)/.build
