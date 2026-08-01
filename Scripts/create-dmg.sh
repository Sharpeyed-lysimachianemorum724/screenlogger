#!/usr/bin/env bash
# Create and verify Screenlogger's drag-to-Applications disk image.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP=""
OUTPUT=""
VOLUME_NAME="Screenlogger"
BACKGROUND="$ROOT/Packaging/InstallerBackground.svg"
REPLACE=0

usage() {
  cat <<'USAGE'
Usage: Scripts/create-dmg.sh --app APP --output FILE [options]

Options:
  --app APP            Screenlogger.app to package.
  --output FILE        Destination .dmg file.
  --volume-name NAME   Mounted volume name (default: Screenlogger).
  --background FILE    660x420 SVG installer background.
  --replace            Replace an existing destination file.
  -h, --help           Show this help.
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
    --app)
      require_value "$1" "${2:-}"
      APP="$2"
      shift 2
      ;;
    --output)
      require_value "$1" "${2:-}"
      OUTPUT="$2"
      shift 2
      ;;
    --volume-name)
      require_value "$1" "${2:-}"
      VOLUME_NAME="$2"
      shift 2
      ;;
    --background)
      require_value "$1" "${2:-}"
      BACKGROUND="$2"
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

if [[ -z "$APP" || -z "$OUTPUT" ]]; then
  usage >&2
  exit 2
fi
if [[ "$APP" != /* ]]; then
  APP="$ROOT/$APP"
fi
if [[ "$BACKGROUND" != /* ]]; then
  BACKGROUND="$ROOT/$BACKGROUND"
fi
if [[ ! -d "$APP" || -L "$APP" || "$(basename "$APP")" != "Screenlogger.app" ]]; then
  echo "error: --app must be a real Screenlogger.app directory" >&2
  exit 1
fi
if [[ ! -f "$BACKGROUND" || -L "$BACKGROUND" ]]; then
  echo "error: installer background is missing or is a symlink: $BACKGROUND" >&2
  exit 1
fi
if [[ "$OUTPUT" != *.dmg || "$OUTPUT" == *$'\n'* ]]; then
  echo "error: output must be a .dmg path without newlines" >&2
  exit 1
fi
if [[ ! "$VOLUME_NAME" =~ ^[[:alnum:]][[:alnum:]\ ._-]{0,26}$ ]]; then
  echo "error: volume name must be 1-27 plain filename characters" >&2
  exit 1
fi

if [[ "$OUTPUT" != /* ]]; then
  OUTPUT="$ROOT/$OUTPUT"
fi
OUTPUT_PARENT="$(dirname "$OUTPUT")"
mkdir -p "$OUTPUT_PARENT"
OUTPUT_PARENT="$(cd "$OUTPUT_PARENT" && pwd -P)"
OUTPUT="$OUTPUT_PARENT/$(basename "$OUTPUT")"
if [[ -L "$OUTPUT" ]]; then
  echo "error: refusing to replace a symlink destination: $OUTPUT" >&2
  exit 1
fi
if [[ -e "$OUTPUT" && "$REPLACE" -ne 1 ]]; then
  echo "error: disk image already exists (use --replace deliberately): $OUTPUT" >&2
  exit 1
fi

for command_name in ditto hdiutil osascript sips stat tiffutil; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "error: required tool is unavailable: $command_name" >&2
    exit 1
  fi
done

WORK_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/screenlogger-dmg.XXXXXX")"
STAGE="$WORK_ROOT/stage"
MOUNT_POINT="/Volumes/$VOLUME_NAME"
VERIFY_MOUNT="$WORK_ROOT/verify"
RW_DMG="$WORK_ROOT/Screenlogger-read-write.dmg"
FINAL_DMG="$WORK_ROOT/Screenlogger.dmg"
BACKGROUND_1X="$WORK_ROOT/installer-background-1x.tiff"
BACKGROUND_2X="$WORK_ROOT/installer-background-2x.tiff"
MOUNTED_PATH=""

detach_if_mounted() {
  if [[ -n "$MOUNTED_PATH" ]]; then
    /usr/bin/hdiutil detach "$MOUNTED_PATH" -force >/dev/null 2>&1 || true
  fi
  MOUNTED_PATH=""
}

cleanup_dmg_work() {
  detach_if_mounted
  rm -rf -- "$WORK_ROOT"
}
trap cleanup_dmg_work EXIT INT TERM

mkdir -p "$STAGE/.background" "$VERIFY_MOUNT"
/usr/bin/ditto "$APP" "$STAGE/Screenlogger.app"
/bin/ln -s /Applications "$STAGE/Applications"

/usr/bin/sips -s format tiff "$BACKGROUND" --out "$BACKGROUND_1X" >/dev/null
/usr/bin/sips -s format tiff --resampleWidth 1320 "$BACKGROUND" --out "$BACKGROUND_2X" >/dev/null
BACKGROUND_WIDTH="$(/usr/bin/sips -g pixelWidth "$BACKGROUND_1X" | /usr/bin/awk '/pixelWidth/ {print $2}')"
BACKGROUND_HEIGHT="$(/usr/bin/sips -g pixelHeight "$BACKGROUND_1X" | /usr/bin/awk '/pixelHeight/ {print $2}')"
if [[ "$BACKGROUND_WIDTH" != "660" || "$BACKGROUND_HEIGHT" != "420" ]]; then
  echo "error: installer background must render at exactly 660x420 pixels" >&2
  exit 1
fi
/usr/bin/tiffutil -cathidpicheck "$BACKGROUND_1X" "$BACKGROUND_2X" \
  -out "$STAGE/.background/installer-background.tiff" >/dev/null

APP_ICON="$STAGE/Screenlogger.app/Contents/Resources/AppIcon.icns"
if [[ -f "$APP_ICON" && ! -L "$APP_ICON" ]]; then
  /usr/bin/ditto "$APP_ICON" "$STAGE/.VolumeIcon.icns"
fi

/usr/bin/hdiutil create \
  -srcfolder "$STAGE" \
  -volname "$VOLUME_NAME" \
  -fs HFS+ \
  -format UDRW \
  -ov \
  "$RW_DMG" >/dev/null

if [[ -e "$MOUNT_POINT" ]]; then
  echo "error: another volume is already mounted at $MOUNT_POINT" >&2
  exit 1
fi
ATTACH_OUTPUT="$(/usr/bin/hdiutil attach \
  -readwrite \
  -noverify \
  -noautoopen \
  -owners off \
  "$RW_DMG")"
if ! /usr/bin/grep -Fq "$MOUNT_POINT" <<<"$ATTACH_OUTPUT"; then
  echo "error: disk image did not mount at its expected volume path" >&2
  exit 1
fi
MOUNTED_PATH="$MOUNT_POINT"

if [[ -f "$MOUNT_POINT/.VolumeIcon.icns" ]] && command -v SetFile >/dev/null 2>&1; then
  SetFile -a C "$MOUNT_POINT"
fi

/usr/bin/osascript - "$VOLUME_NAME" <<'APPLESCRIPT'
on run arguments
    set volumeName to item 1 of arguments
    tell application "Finder"
        tell disk volumeName
            set backgroundFile to file ".background:installer-background.tiff"
            open
            tell container window
                set current view to icon view
                set toolbar visible to false
                set statusbar visible to false
                set pathbar visible to false
                set sidebar width to 0
                set bounds to {120, 120, 780, 540}
            end tell
            tell icon view options of container window
                set arrangement to not arranged
                set icon size to 100
                set text size to 12
                set background picture to backgroundFile
            end tell
            set position of item "Screenlogger.app" to {175, 222}
            set position of item "Applications" to {485, 222}
            update without registering applications
            delay 2
            close
        end tell
    end tell
end run
APPLESCRIPT

if [[ ! -f "$MOUNT_POINT/.DS_Store" ]]; then
  echo "error: Finder did not persist the installer layout" >&2
  exit 1
fi
/bin/sync
/usr/bin/hdiutil detach "$MOUNT_POINT" >/dev/null
MOUNTED_PATH=""

/usr/bin/hdiutil convert "$RW_DMG" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -ov \
  -o "$FINAL_DMG" >/dev/null

/usr/bin/hdiutil verify "$FINAL_DMG" >/dev/null
/usr/bin/hdiutil attach \
  -readonly \
  -noverify \
  -nobrowse \
  -owners off \
  -mountpoint "$VERIFY_MOUNT" \
  "$FINAL_DMG" >/dev/null
MOUNTED_PATH="$VERIFY_MOUNT"

if [[ ! -d "$VERIFY_MOUNT/Screenlogger.app" \
  || ! -L "$VERIFY_MOUNT/Applications" \
  || "$(/usr/bin/readlink "$VERIFY_MOUNT/Applications")" != "/Applications" \
  || ! -f "$VERIFY_MOUNT/.background/installer-background.tiff" \
  || ! -f "$VERIFY_MOUNT/.DS_Store" ]]; then
  echo "error: verified disk image is missing its app, Applications link, background, or layout" >&2
  exit 1
fi

/usr/bin/hdiutil detach "$VERIFY_MOUNT" >/dev/null
MOUNTED_PATH=""
/bin/mv -f "$FINAL_DMG" "$OUTPUT"

echo "disk image verified"
echo "asset: $OUTPUT"
echo "bytes: $(/usr/bin/stat -f '%z' "$OUTPUT")"
