# Dict

Dict is a native macOS menu bar app, written in Swift; the planned UI is AppKit windows hosting SwiftUI views.
It requires macOS 15 or later and is licensed under GPL-3.0-or-later.
The app is at the skeleton stage: a menu bar icon with About and Quit.

## Layout

- `App/` holds the macOS app target: sources, resources (String Catalog with English and Simplified Chinese) and unit tests.
- `Packages/DictCore/` is a local Swift package for platform-independent logic, shared with a future iOS app.
- `Config/` holds the xcconfig files; the product name, bundle identifier and signing team are defined only in `Config/Base.xcconfig`.
- `project.yml` is the XcodeGen spec; the generated `DictApp.xcodeproj` is not tracked.
- `scripts/` holds the smoke test and packaging scripts.

## Build and run

Install XcodeGen once with `brew install xcodegen`.

```sh
make generate   # create DictApp.xcodeproj from project.yml
make build      # Debug build: "Dict Dev", bundle id au.ibra.dict.dev
make run        # build and launch the Debug app
make test       # DictCore tests, app unit tests, end-to-end smoke test
make lint       # swift format lint (Xcode's bundled swift-format)
make format     # apply swift format in place
make package    # Release build zipped into build/dist/
```

Pass `CONFIG=Release` to `build`, `run` or `smoke` to use the Release build ("Dict", bundle id `au.ibra.dict`).
Debug and Release builds have different names and bundle identifiers, so both can be installed side by side with separate Accessibility grants.
Builds are signed with the local Apple Development certificate, with the Hardened Runtime and without the App Sandbox.
The stable signing identity keeps Accessibility grants across rebuilds.

The smoke test launches the app, finds its menu bar item through the Accessibility API, and quits it.
It never takes focus or sends key events, but the terminal running it needs Accessibility permission.

## Distribution

`make package` produces a zip signed with the Apple Development certificate.
It is not notarized, so Gatekeeper blocks it on other Macs after download.
Notarized distribution needs a Developer ID Application certificate and a `notarytool` keychain profile named in `DICT_NOTARY_PROFILE`; see `scripts/package.sh`.
