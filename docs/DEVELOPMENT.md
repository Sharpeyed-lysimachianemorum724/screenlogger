# Development

## Requirements

- macOS 14 or later
- full Xcode
- Git

The repository includes a pinned XcodeGen launcher that downloads the expected
tool into ignored `.tools` state when needed.

## Build and test

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
Scripts/check-repository.sh
xcrun swift-format lint --strict --configuration .swift-format --recursive Sources Tests UITests
swift test
Scripts/xcodegen.sh generate
Scripts/build.sh
```

Run app presentation tests with the `ScreenlogAppTests` scheme. Run routed UI
tests with `Scripts/test-ui.sh`. UI fixtures use isolated temporary data and
preferences and never touch the user's Library or macOS permission database.

## Source layout

```text
Sources/ScreenlogApp       Application state, services, and SwiftUI views
Sources/ScreenlogCLI       Terminal client and skill lifecycle
Sources/ScreenlogCore      Capture, recognition, storage, search, and IPC
Tests                      Unit and integration tests
UITests                    Routed application and visual regression tests
Tools/ScreenlogPerformance Deterministic performance harness
Scripts                    Build, install, validation, and release automation
Packaging                  DMG presentation assets and archive instructions
```

## Repository rules

- Keep tracked text ASCII-only.
- Use Screenlogger for the product and `screenlog` for the command.
- Keep app-owned database access behind `Store` and the IPC boundary.
- Use prompt-free permission checks outside explicit user actions.
- Preserve user content on failed installs, restores, deletions, and upgrades.
- Do not commit build products, test evidence, personal data, or scratch files.
