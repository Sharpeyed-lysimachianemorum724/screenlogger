#!/usr/bin/env bash
# Build, ad-hoc sign, validate, and package a universal Screenlogger release.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="$ROOT/build/releases"
PRODUCTS=""
EXPECTED_TAG=""
REPLACE=0

usage() {
  cat <<'USAGE'
Usage: Scripts/package-release.sh [options]

Options:
  --products DIR       Package existing universal Release products instead of building.
  --output DIR         Write release assets here (default: build/releases).
  --expected-tag TAG   Require TAG to equal v<app marketing version>.
  --replace            Replace exact same-version assets already in the output directory.
  -h, --help           Show this help.

This release path applies complete local ad-hoc signatures and verifies the
result. It never uses Developer ID, notarizes, publishes, or replaces an
installed application.
USAGE
}

require_value() {
  local option="$1"
  local value="${2:-}"
  if [[ -z "$value" ]]; then
    echo "error: $option requires a value" >&2
    exit 2
  fi
}

while (( $# > 0 )); do
  case "$1" in
    --products)
      require_value "$1" "${2:-}"
      PRODUCTS="$2"
      shift 2
      ;;
    --output)
      require_value "$1" "${2:-}"
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --expected-tag)
      require_value "$1" "${2:-}"
      EXPECTED_TAG="$2"
      shift 2
      ;;
    --replace)
      REPLACE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "$OUTPUT_DIR" != /* ]]; then
  OUTPUT_DIR="$ROOT/$OUTPUT_DIR"
fi
if [[ "$OUTPUT_DIR" == "/" || "$OUTPUT_DIR" == *$'\n'* ]]; then
  echo "error: output directory must be a non-root path without newlines" >&2
  exit 1
fi
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd -P)"

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
if [[ -z "${DEVELOPER_DIR:-}" || ! -d "$DEVELOPER_DIR" ]]; then
  echo "error: a complete Xcode installation is required" >&2
  exit 1
fi

for command_name in codesign ditto find hdiutil lipo otool plutil shasum stat xcodebuild; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "error: required tool is unavailable: $command_name" >&2
    exit 1
  fi
done

WORK_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/screenlogger-package.XXXXXX")"
DMG_VERIFY_MOUNT=""
cleanup_package_work() {
  if [[ -n "$DMG_VERIFY_MOUNT" ]]; then
    /usr/bin/hdiutil detach "$DMG_VERIFY_MOUNT" -force >/dev/null 2>&1 || true
  fi
  rm -rf -- "$WORK_ROOT"
}
trap cleanup_package_work EXIT INT TERM

if [[ -z "$PRODUCTS" ]]; then
  "$ROOT/Scripts/check-repository.sh"
  "$ROOT/Scripts/check-source-safety.sh"
  "$ROOT/Scripts/xcodegen.sh" generate

  DERIVED_DATA="$WORK_ROOT/DerivedData"
  xcodebuild \
    -project "$ROOT/Screenlog.xcodeproj" \
    -scheme Screenlog \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$DERIVED_DATA" \
    ARCHS="arm64 x86_64" \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGNING_ALLOWED=NO \
    build
  PRODUCTS="$DERIVED_DATA/Build/Products/Release"
elif [[ "$PRODUCTS" != /* ]]; then
  PRODUCTS="$ROOT/$PRODUCTS"
fi

if [[ ! -d "$PRODUCTS" ]]; then
  echo "error: Release products directory not found: $PRODUCTS" >&2
  exit 1
fi
PRODUCTS="$(cd "$PRODUCTS" && pwd -P)"

VERSION_VERIFICATION_ARGS=(--products "$PRODUCTS")
if [[ -n "$EXPECTED_TAG" ]]; then
  VERSION_VERIFICATION_ARGS+=(--tag "$EXPECTED_TAG")
fi
"$ROOT/Scripts/verify-version.sh" "${VERSION_VERIFICATION_ARGS[@]}"
"$ROOT/Scripts/test-release-verification.sh" "$PRODUCTS"

APP="$PRODUCTS/Screenlogger.app"
CLI="$PRODUCTS/screenlog"
FRAMEWORK="$APP/Contents/Frameworks/ScreenlogCore.framework"
APP_PLIST="$APP/Contents/Info.plist"
for required_path in "$APP" "$CLI" "$FRAMEWORK" "$APP_PLIST"; do
  if [[ ! -e "$required_path" ]]; then
    echo "error: required Release product is missing: $required_path" >&2
    exit 1
  fi
done

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PLIST")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PLIST")"
MINIMUM_MACOS="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP_PLIST")"
SOURCE_EPOCH="${SOURCE_DATE_EPOCH:-}"
if [[ -z "$SOURCE_EPOCH" ]] && command -v git >/dev/null 2>&1; then
  SOURCE_EPOCH="$(git -C "$ROOT" log -1 --format=%ct 2>/dev/null || true)"
fi
if [[ ! "$SOURCE_EPOCH" =~ ^[0-9]+$ ]]; then
  echo "error: SOURCE_DATE_EPOCH must be an integer (or package from a Git checkout)" >&2
  exit 1
fi
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
  echo "error: app marketing version is not release-safe: $VERSION" >&2
  exit 1
fi
if [[ ! "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "error: app build number is not a positive integer: $BUILD_NUMBER" >&2
  exit 1
fi
if [[ -n "$EXPECTED_TAG" && "$EXPECTED_TAG" != "v$VERSION" ]]; then
  echo "error: release tag $EXPECTED_TAG does not match app version v$VERSION" >&2
  exit 1
fi

# Make repeated packaging of the same verified products stable. Build UUIDs are
# intentionally preserved; this only normalizes archive metadata to the tagged
# source commit rather than the machine's build time.
ARCHIVE_TIMESTAMP="$(/bin/date -r "$SOURCE_EPOCH" '+%Y%m%d%H%M.%S')"
normalize_tree_timestamps() {
  local tree="$1"
  /usr/bin/find -s "$tree" -depth -exec /usr/bin/touch -h -t "$ARCHIVE_TIMESTAMP" {} +
}

PACKAGE_NAME="Screenlogger-v$VERSION-macos-universal"
STAGE="$WORK_ROOT/$PACKAGE_NAME"
mkdir -p "$STAGE/CLI/skill"
/usr/bin/ditto "$APP" "$STAGE/Screenlogger.app"
/usr/bin/install -m 755 "$CLI" "$STAGE/CLI/screenlog"
/usr/bin/ditto "$FRAMEWORK" "$STAGE/CLI/ScreenlogCore.framework"
/usr/bin/ditto \
  "$ROOT/Resources/skill/screenlog-cli-skill" \
  "$STAGE/CLI/skill/screenlog-cli-skill"
/usr/bin/install -m 644 "$ROOT/Packaging/INSTALL.md" "$STAGE/INSTALL.md"
/usr/bin/install -m 644 "$ROOT/LICENSE" "$STAGE/LICENSE"
/usr/bin/install -m 644 "$ROOT/THIRD_PARTY_NOTICES.md" "$STAGE/THIRD_PARTY_NOTICES.md"

# Xcode's CODE_SIGNING_ALLOWED=NO build leaves linker-generated placeholder
# signatures whose identity is not the app's bundle identifier and which do not
# bind Info.plist or Resources. Replace them inside-out in the disposable stage.
"$ROOT/Scripts/sign-release-adhoc.sh" \
  "$STAGE/Screenlogger.app" \
  "$STAGE/CLI/screenlog"

sha256() {
  /usr/bin/shasum -a 256 "$1" | /usr/bin/awk '{print $1}'
}

PACKAGE_MANIFEST_PLIST="$WORK_ROOT/package-manifest.plist"
/usr/bin/plutil -create xml1 "$PACKAGE_MANIFEST_PLIST"
/usr/bin/plutil -insert schemaVersion -integer 1 "$PACKAGE_MANIFEST_PLIST"
/usr/bin/plutil -insert product -string Screenlogger "$PACKAGE_MANIFEST_PLIST"
/usr/bin/plutil -insert version -string "$VERSION" "$PACKAGE_MANIFEST_PLIST"
/usr/bin/plutil -insert build -string "$BUILD_NUMBER" "$PACKAGE_MANIFEST_PLIST"
/usr/bin/plutil -insert minimumMacOS -string "$MINIMUM_MACOS" "$PACKAGE_MANIFEST_PLIST"
/usr/bin/plutil -insert architectures -json '["arm64","x86_64"]' "$PACKAGE_MANIFEST_PLIST"
/usr/bin/plutil -insert signing -string ad-hoc "$PACKAGE_MANIFEST_PLIST"
/usr/bin/plutil -insert sourceDateEpoch -integer "$SOURCE_EPOCH" "$PACKAGE_MANIFEST_PLIST"
/usr/bin/plutil -insert appExecutableSHA256 -string \
  "$(sha256 "$STAGE/Screenlogger.app/Contents/MacOS/Screenlogger")" \
  "$PACKAGE_MANIFEST_PLIST"
/usr/bin/plutil -insert bundledCLISHA256 -string \
  "$(sha256 "$STAGE/Screenlogger.app/Contents/MacOS/screenlog")" \
  "$PACKAGE_MANIFEST_PLIST"
/usr/bin/plutil -insert standaloneCLISHA256 -string \
  "$(sha256 "$STAGE/CLI/screenlog")" \
  "$PACKAGE_MANIFEST_PLIST"
/usr/bin/plutil -insert assistantSkillSHA256 -string \
  "$(sha256 "$STAGE/CLI/skill/screenlog-cli-skill/SKILL.md")" \
  "$PACKAGE_MANIFEST_PLIST"
/usr/bin/plutil -convert json -o "$STAGE/package-manifest.json" "$PACKAGE_MANIFEST_PLIST"

"$ROOT/Scripts/check-release.sh" --ad-hoc \
  "$STAGE/Screenlogger.app" \
  "$STAGE/CLI/screenlog"

unset DYLD_LIBRARY_PATH DYLD_FRAMEWORK_PATH \
  DYLD_FALLBACK_LIBRARY_PATH DYLD_FALLBACK_FRAMEWORK_PATH || true
if [[ "$("$STAGE/CLI/screenlog" --version)" != "$VERSION" ]]; then
  echo "error: staged CLI version does not match app version $VERSION" >&2
  exit 1
fi

# Reuse the existing destructive-lifecycle regression only inside a disposable
# product tree assembled from the exact staged bytes.
LIFECYCLE_PRODUCTS="$WORK_ROOT/lifecycle-products"
mkdir -p "$LIFECYCLE_PRODUCTS"
/usr/bin/ditto "$STAGE/Screenlogger.app" "$LIFECYCLE_PRODUCTS/Screenlogger.app"
/usr/bin/install -m 755 "$STAGE/CLI/screenlog" "$LIFECYCLE_PRODUCTS/screenlog"
/usr/bin/ditto \
  "$STAGE/CLI/ScreenlogCore.framework" \
  "$LIFECYCLE_PRODUCTS/ScreenlogCore.framework"
"$ROOT/Scripts/test-install-lifecycle.sh" "$LIFECYCLE_PRODUCTS"

ARCHIVE_TMP="$WORK_ROOT/$PACKAGE_NAME.zip"
# Validation reads update access times on common macOS volumes. Normalize at
# the last possible moment because ditto records both access and modification
# timestamps in its ZIP metadata.
normalize_tree_timestamps "$STAGE"
/usr/bin/ditto -c -k --keepParent --norsrc --noextattr --noqtn --noacl \
  "$STAGE" "$ARCHIVE_TMP"

# Validate the extracted archive, not only the pre-archive staging directory.
EXTRACT_ROOT="$WORK_ROOT/extracted"
mkdir -p "$EXTRACT_ROOT"
/usr/bin/ditto -x -k "$ARCHIVE_TMP" "$EXTRACT_ROOT"
EXTRACTED="$EXTRACT_ROOT/$PACKAGE_NAME"
"$ROOT/Scripts/check-release.sh" --ad-hoc \
  "$EXTRACTED/Screenlogger.app" \
  "$EXTRACTED/CLI/screenlog"
if [[ "$("$EXTRACTED/CLI/screenlog" --version)" != "$VERSION" ]]; then
  echo "error: extracted CLI version does not match app version $VERSION" >&2
  exit 1
fi

ARCHIVE_SHA256="$(sha256 "$ARCHIVE_TMP")"
ARCHIVE_SIZE="$(/usr/bin/stat -f '%z' "$ARCHIVE_TMP")"
ARCHIVE_CHECKSUM_TMP="$WORK_ROOT/$PACKAGE_NAME.zip.sha256"
printf '%s  %s\n' "$ARCHIVE_SHA256" "$PACKAGE_NAME.zip" > "$ARCHIVE_CHECKSUM_TMP"

# The ZIP remains a complete technical archive. The DMG is the primary macOS
# installation surface and contains the exact same verified app bytes.
DMG_TMP="$WORK_ROOT/$PACKAGE_NAME.dmg"
"$ROOT/Scripts/create-dmg.sh" \
  --app "$STAGE/Screenlogger.app" \
  --output "$DMG_TMP" \
  --volume-name "Screenlogger $VERSION"

DMG_VERIFY_MOUNT="$WORK_ROOT/dmg-verify"
mkdir -p "$DMG_VERIFY_MOUNT"
/usr/bin/hdiutil attach \
  -readonly \
  -noverify \
  -nobrowse \
  -owners off \
  -mountpoint "$DMG_VERIFY_MOUNT" \
  "$DMG_TMP" >/dev/null
"$ROOT/Scripts/check-release.sh" --ad-hoc \
  "$DMG_VERIFY_MOUNT/Screenlogger.app" \
  "$EXTRACTED/CLI/screenlog"
if [[ "$(sha256 "$DMG_VERIFY_MOUNT/Screenlogger.app/Contents/MacOS/Screenlogger")" \
  != "$(sha256 "$STAGE/Screenlogger.app/Contents/MacOS/Screenlogger")" ]]; then
  echo "error: disk image app executable does not match the verified staged app" >&2
  exit 1
fi
/usr/bin/hdiutil detach "$DMG_VERIFY_MOUNT" >/dev/null
DMG_VERIFY_MOUNT=""

DMG_SHA256="$(sha256 "$DMG_TMP")"
DMG_SIZE="$(/usr/bin/stat -f '%z' "$DMG_TMP")"
DMG_CHECKSUM_TMP="$WORK_ROOT/$PACKAGE_NAME.dmg.sha256"
printf '%s  %s\n' "$DMG_SHA256" "$PACKAGE_NAME.dmg" > "$DMG_CHECKSUM_TMP"

RELEASE_MANIFEST_PLIST="$WORK_ROOT/release-manifest.plist"
RELEASE_MANIFEST_TMP="$WORK_ROOT/$PACKAGE_NAME.json"
/usr/bin/plutil -create xml1 "$RELEASE_MANIFEST_PLIST"
/usr/bin/plutil -insert schemaVersion -integer 2 "$RELEASE_MANIFEST_PLIST"
/usr/bin/plutil -insert product -string Screenlogger "$RELEASE_MANIFEST_PLIST"
/usr/bin/plutil -insert version -string "$VERSION" "$RELEASE_MANIFEST_PLIST"
/usr/bin/plutil -insert build -string "$BUILD_NUMBER" "$RELEASE_MANIFEST_PLIST"
/usr/bin/plutil -insert minimumMacOS -string "$MINIMUM_MACOS" "$RELEASE_MANIFEST_PLIST"
/usr/bin/plutil -insert architectures -json '["arm64","x86_64"]' "$RELEASE_MANIFEST_PLIST"
/usr/bin/plutil -insert signing -string ad-hoc "$RELEASE_MANIFEST_PLIST"
/usr/bin/plutil -insert sourceDateEpoch -integer "$SOURCE_EPOCH" "$RELEASE_MANIFEST_PLIST"
/usr/bin/plutil -insert assetName -string "$PACKAGE_NAME.dmg" "$RELEASE_MANIFEST_PLIST"
/usr/bin/plutil -insert assetBytes -integer "$DMG_SIZE" "$RELEASE_MANIFEST_PLIST"
/usr/bin/plutil -insert assetSHA256 -string "$DMG_SHA256" "$RELEASE_MANIFEST_PLIST"
/usr/bin/plutil -insert archiveName -string "$PACKAGE_NAME.zip" "$RELEASE_MANIFEST_PLIST"
/usr/bin/plutil -insert archiveBytes -integer "$ARCHIVE_SIZE" "$RELEASE_MANIFEST_PLIST"
/usr/bin/plutil -insert archiveSHA256 -string "$ARCHIVE_SHA256" "$RELEASE_MANIFEST_PLIST"
/usr/bin/plutil -insert packageManifestSHA256 -string \
  "$(sha256 "$STAGE/package-manifest.json")" \
  "$RELEASE_MANIFEST_PLIST"
/usr/bin/plutil -convert json -o "$RELEASE_MANIFEST_TMP" "$RELEASE_MANIFEST_PLIST"

DSYM_ARCHIVE_TMP=""
DSYM_STAGE="$WORK_ROOT/$PACKAGE_NAME-dSYMs"
for dsym_name in \
  Screenlogger.app.dSYM \
  screenlog.dSYM \
  ScreenlogCore.framework.dSYM; do
  if [[ -d "$PRODUCTS/$dsym_name" ]]; then
    mkdir -p "$DSYM_STAGE"
    /usr/bin/ditto "$PRODUCTS/$dsym_name" "$DSYM_STAGE/$dsym_name"
  fi
done
if [[ -d "$DSYM_STAGE" ]]; then
  normalize_tree_timestamps "$DSYM_STAGE"
  DSYM_ARCHIVE_TMP="$WORK_ROOT/$PACKAGE_NAME-dSYMs.zip"
  /usr/bin/ditto -c -k --keepParent --norsrc --noextattr --noqtn --noacl \
    "$DSYM_STAGE" "$DSYM_ARCHIVE_TMP"
fi

OUTPUTS=(
  "$OUTPUT_DIR/$PACKAGE_NAME.dmg"
  "$OUTPUT_DIR/$PACKAGE_NAME.dmg.sha256"
  "$OUTPUT_DIR/$PACKAGE_NAME.zip"
  "$OUTPUT_DIR/$PACKAGE_NAME.zip.sha256"
  "$OUTPUT_DIR/$PACKAGE_NAME.json"
)
if [[ -n "$DSYM_ARCHIVE_TMP" ]]; then
  OUTPUTS+=("$OUTPUT_DIR/$PACKAGE_NAME-dSYMs.zip")
fi
if (( REPLACE == 0 )); then
  for output_path in "${OUTPUTS[@]}"; do
    if [[ -e "$output_path" ]]; then
      echo "error: release asset already exists (use --replace deliberately): $output_path" >&2
      exit 1
    fi
  done
fi

/bin/mv -f "$DMG_TMP" "$OUTPUT_DIR/$PACKAGE_NAME.dmg"
/bin/mv -f "$DMG_CHECKSUM_TMP" "$OUTPUT_DIR/$PACKAGE_NAME.dmg.sha256"
/bin/mv -f "$ARCHIVE_TMP" "$OUTPUT_DIR/$PACKAGE_NAME.zip"
/bin/mv -f "$ARCHIVE_CHECKSUM_TMP" "$OUTPUT_DIR/$PACKAGE_NAME.zip.sha256"
/bin/mv -f "$RELEASE_MANIFEST_TMP" "$OUTPUT_DIR/$PACKAGE_NAME.json"
if [[ -n "$DSYM_ARCHIVE_TMP" ]]; then
  /bin/mv -f "$DSYM_ARCHIVE_TMP" "$OUTPUT_DIR/$PACKAGE_NAME-dSYMs.zip"
fi

echo "release package verified"
echo "version: $VERSION ($BUILD_NUMBER)"
echo "installer: $OUTPUT_DIR/$PACKAGE_NAME.dmg"
echo "installer sha256: $DMG_SHA256"
echo "archive: $OUTPUT_DIR/$PACKAGE_NAME.zip"
echo "archive sha256: $ARCHIVE_SHA256"
echo "manifest: $OUTPUT_DIR/$PACKAGE_NAME.json"
if [[ -n "$DSYM_ARCHIVE_TMP" ]]; then
  echo "symbols: $OUTPUT_DIR/$PACKAGE_NAME-dSYMs.zip"
fi
