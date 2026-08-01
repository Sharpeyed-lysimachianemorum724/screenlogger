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

The tag must be exactly `v<MARKETING_VERSION>`.

## Build locally

```sh
export SOURCE_DATE_EPOCH="$(git show -s --format=%ct HEAD)"
Scripts/package-release.sh \
  --expected-tag v0.1.1 \
  --output build/releases
Scripts/generate-update-feed.sh \
  --archive build/releases/Screenlogger-v0.1.1-macos-universal.dmg \
  --output build/releases/appcast.xml \
  --tag v0.1.1
```

Packaging builds universal arm64 and x86_64 products, applies complete ad-hoc
signatures, verifies nested code, Sparkle, and resources, exercises install and
removal in a disposable home, validates extracted ZIP and mounted DMG contents,
and writes SHA-256 files plus a JSON manifest. The update-feed command signs the
DMG and appcast with the `screenlogger` Sparkle key in the local Keychain.

Ad-hoc builds are not Developer ID signed or notarized. Hardened Runtime remains
off for this phase because nested library validation requires a Developer ID team
identity. Each differently built ad-hoc release can require fresh macOS grants.

## Publish a prerelease

Push `main` and wait for CI before creating a version tag. Then:

```sh
git tag -a v0.1.1 -m "Screenlogger v0.1.1"
git push origin refs/tags/v0.1.1
```

The Release workflow verifies the immutable tag, repeats the quality gates,
builds the universal package, signs `appcast.xml`, and creates a draft
prerelease. The build requires the `SPARKLE_ED_PRIVATE_KEY` repository secret.
The private key must never be printed, committed, or stored in a release asset.

Download the draft assets to a temporary directory and verify both checksum
files before publishing:

```sh
gh release download v0.1.1 --dir "$TMPDIR/screenlogger-release-v0.1.1"
cd "$TMPDIR/screenlogger-release-v0.1.1"
shasum -a 256 -c Screenlogger-v0.1.1-macos-universal.dmg.sha256
shasum -a 256 -c Screenlogger-v0.1.1-macos-universal.zip.sha256
grep -F 'sparkle:edSignature=' appcast.xml
grep -F '<!-- sparkle-signatures:' appcast.xml
gh release edit v0.1.1 --draft=false --prerelease
```

The workflow refuses to overwrite an already published release. Publishing the
release triggers the Update Feed workflow, which deploys that exact signed
`appcast.xml` to GitHub Pages. Confirm
`https://radkawar.github.io/screenlogger/appcast.xml` before announcing the
release.

The Ed25519 key is the trust anchor for ad-hoc signed updates. Keep the
`screenlogger` Keychain item backed up. Losing both that item and the Actions
secret prevents existing builds from accepting future updates until Developer
ID key rotation is available.

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
