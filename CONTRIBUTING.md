# Contributing

Screenlogger is a native macOS application written in Swift. Contributions
should preserve its privacy boundary, predictable native behavior, and tested
release contracts.

## Before making a change

- Read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).
- Follow [docs/styling.md](docs/styling.md) for interface work.
- Add or update tests for behavior changes.
- Do not read, modify, or commit a real Screenlogger Library.
- Do not add generated output, local paths, credentials, or borrowed product
  language.

## Local checks

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
Scripts/check-repository.sh
xcrun swift-format lint --strict --configuration .swift-format --recursive Sources Tests UITests
swift test
Scripts/xcodegen.sh generate
git diff --exit-code -- Screenlog.xcodeproj/project.pbxproj
Scripts/build.sh
```

Run `Scripts/test-ui.sh` when changing navigation, accessibility labels,
permission presentation, Library, Timeline, or Settings. Run
`Scripts/measure-performance.sh` when changing search, media decoding, Timeline
loading, capture cadence, or storage queries.

## Pull requests

Explain the user-visible outcome, privacy impact, failure behavior, and tests.
Keep changes focused. Do not mix refactoring, generated project updates, and
unrelated product changes without a clear reason.

## Releases

Only maintainers create version tags and publish artifacts. The release process
is documented in [docs/RELEASING.md](docs/RELEASING.md).
