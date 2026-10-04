# Dict

Dict is a native macOS menu bar app, written in Swift; the planned UI is AppKit windows hosting SwiftUI views.
It requires macOS 15 or later and is licensed under GPL-3.0-or-later.
Select text in any app and press the Read shortcut: Dict reads the selection and shows its translation in a panel next to it.
It streams the translation from a model with your own API key, or from Ollama on the Mac.
Without a model it uses Apple Translation, but only for languages already installed on the Mac; otherwise the panel asks for a key.
A first-run window asks for Accessibility permission, the Read shortcut and an API key (which can wait), then translates a sample in the panel.
Writing help (the Write shortcut), word lookup and the vocabulary come in later milestones.

## Layout

- `App/` holds the macOS app target: sources, resources (String Catalog with English and Simplified Chinese) and unit tests.
- `Packages/DictCore/` is a local Swift package for platform-independent logic, shared with a future iOS app; it also holds the `DictEval` prompt-evaluation tool.
- `Fixtures/CaptureFixture/` is a test app for end-to-end capture and replace tests; `make build` builds it too.
- `Config/` holds the xcconfig files; the product name, bundle identifier and signing team are defined only in `Config/Base.xcconfig`.
- `project.yml` is the XcodeGen spec; the generated `DictApp.xcodeproj` is not tracked.
- `scripts/` holds the smoke test, packaging and end-to-end driver scripts.
- `Design/` holds the architecture document and the M1 file-ownership plan.

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
make window-test  # first-run, Settings and About windows come up in front (takes focus)
make e2e        # capture scenarios on the fixture app (takes focus)
make matrix     # capture matrix on real apps (takes focus)
make eval SUITE=direction  # prompt evaluation against a real model (reads .env)
```

Pass `CONFIG=Release` to `build`, `run` or `smoke` to use the Release build ("Dict", bundle id `au.ibra.dict`).
Debug and Release builds have different names and bundle identifiers, so both can be installed side by side with separate Accessibility grants.
Builds are signed with the local Apple Development certificate, with the Hardened Runtime and without the App Sandbox.
The stable signing identity keeps Accessibility grants across rebuilds.

The smoke test launches the app with `--no-onboarding`, finds its menu bar item through the Accessibility API, and quits it.
It never takes focus or sends key events, but the terminal running it needs Accessibility permission.
The window test launches the app through Launch Services as `open` does and checks that the first-run window, and Settings and About opened from the menu bar item, come up as the frontmost, key window.
It forces the first-run window with the launch argument `-onboarding.completed NO`, so the user's preferences are never written.
It takes focus, so it is not part of `make test` and holds `/private/tmp/dict-ui.lock` while it runs.

## Distribution

`make package` produces a zip signed with the Apple Development certificate.
It is not notarized, so Gatekeeper blocks it on other Macs after download.
Notarized distribution needs a Developer ID Application certificate and a `notarytool` keychain profile named in `DICT_NOTARY_PROFILE`; see `scripts/package.sh`.
