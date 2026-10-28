# Eggscape

A digital "Eierlauf" (egg-and-spoon race) for iPhone. The phone is the spoon: tilt it to keep the egg in the bowl
while your runner races along the track.

## Setup

```bash
brew install xcodegen swiftformat fastlane   # or: make bootstrap (builds XcodeGen + SwiftFormat from source)
make gen                                     # generates Eggscape.xcodeproj from project.yml
make run                                     # builds and launches the app on an iPhone simulator
```

`make help` lists all tasks (`build`, `test`, `test-ui`, `format`, `beta`, `screenshots`, ...).
