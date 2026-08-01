# Releasing

`Sources/ScreenlogCore/Resources/ProductVersion.xcconfig` is the product version
source of truth. `MARKETING_VERSION` uses three-component semantic versioning.
Increment `CURRENT_PROJECT_VERSION` for every shipped build.

## Prepare

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
Scripts/verify-version.sh
Scripts/xcodegen.sh generate
git diff --exit-code -- Screenlog.xcodeproj/project.pbxproj
Scripts/check-repository.sh
swift test
```

The tag must be exactly `v<MARKETING_VERSION>`. For version 0.1.0, use
`v0.1.0`.

## Build locally

```sh
export SOURCE_DATE_EPOCH="$(git show -s --format=%ct HEAD)"
Scripts/package-release.sh \
  --expected-tag v0.1.0 \
  --output build/releases
```

Packaging builds universal arm64 and x86_64 products, applies complete ad-hoc
signatures, verifies nested code and resources, exercises install and removal in
a disposable home, validates extracted ZIP and mounted DMG contents, and writes
SHA-256 files plus a JSON manifest.

Ad-hoc builds are not Developer ID signed or notarized. Hardened Runtime remains
off for this phase because nested library validation requires a Developer ID team
identity. Each differently built ad-hoc release can require fresh macOS grants.

## Publish a prerelease

Push `main` and wait for CI before creating a version tag. Then:

```sh
git tag -a v0.1.0 -m "Screenlogger v0.1.0"
git push origin refs/tags/v0.1.0
```

The Release workflow verifies the immutable tag, repeats the quality gates,
builds the universal package, and creates a draft prerelease. It does not require
repository secrets.

Download the draft assets to a temporary directory and verify both checksum
files before publishing:

```sh
gh release download v0.1.0 --dir "$TMPDIR/screenlogger-release-v0.1.0"
cd "$TMPDIR/screenlogger-release-v0.1.0"
shasum -a 256 -c Screenlogger-v0.1.0-macos-universal.dmg.sha256
shasum -a 256 -c Screenlogger-v0.1.0-macos-universal.zip.sha256
gh release edit v0.1.0 --draft=false --prerelease
```

The workflow refuses to overwrite an already published release.

## Public distribution gate

Before presenting a build as a normal public macOS release:

1. Sign the app, embedded framework, bundled CLI, standalone framework, and
   standalone CLI with Developer ID Application.
2. Enable Hardened Runtime without unsafe library-validation exceptions.
3. Notarize the exact distribution artifact and staple the ticket.
4. Run `Scripts/check-release.sh --signing <app> <cli>` against the final bytes.
5. Verify Gatekeeper acceptance on a clean Mac or virtual machine.

Until those steps are complete, keep releases marked as prereleases and state the
Control-click Open requirement clearly.
