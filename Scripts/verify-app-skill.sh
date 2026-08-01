#!/usr/bin/env bash
# Verify the assistant skill exactly as it will ship inside Screenlogger.app.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="${1:-$ROOT/build/DerivedData/Build/Products/Debug/Screenlogger.app}"
DISCOVERY_MODE="${2:-}"
CANONICAL_SKILL="$ROOT/Resources/skill/screenlog-cli-skill/SKILL.md"
SWIFTPM_SKILL="$ROOT/Sources/ScreenlogCLI/skill/screenlog-cli-skill/SKILL.md"
BUNDLED_SKILL="$APP_PATH/Contents/Resources/skill/screenlog-cli-skill/SKILL.md"
BUNDLED_SKILL_ROOT="$APP_PATH/Contents/Resources/skill"
BUNDLED_SKILL_DIRECTORY="$BUNDLED_SKILL_ROOT/screenlog-cli-skill"
BUNDLED_CLI="$APP_PATH/Contents/MacOS/screenlog"

if [[ "$DISCOVERY_MODE" != "" && "$DISCOVERY_MODE" != "--exercise-discovery" ]]; then
  echo "usage: $0 [Screenlogger.app] [--exercise-discovery]" >&2
  exit 2
fi

if [[ ! -f "$CANONICAL_SKILL" || -L "$CANONICAL_SKILL" ]]; then
  echo "error: canonical Screenlogger skill is missing or is a symlink: $CANONICAL_SKILL" >&2
  exit 1
fi
if [[ ! -f "$SWIFTPM_SKILL" || -L "$SWIFTPM_SKILL" ]]; then
  echo "error: SwiftPM Screenlogger skill is missing or is a symlink: $SWIFTPM_SKILL" >&2
  exit 1
fi
if [[ ! -d "$APP_PATH" ]]; then
  echo "error: app bundle not found: $APP_PATH" >&2
  exit 1
fi
if [[ ! -f "$BUNDLED_SKILL" || -L "$BUNDLED_SKILL" ]]; then
  echo "error: app is missing its regular bundled skill: $BUNDLED_SKILL" >&2
  exit 1
fi

# The skill folder is deliberately an exact three-node contract. This catches
# flattened resources, empty/stale directories, duplicate files, and unusual
# filesystem nodes before they can enter a release archive.
UNEXPECTED_BUNDLED_NODES="$(
  find "$BUNDLED_SKILL_ROOT" -mindepth 1 \
    ! -path "$BUNDLED_SKILL_DIRECTORY" \
    ! -path "$BUNDLED_SKILL" \
    -print
)"
if [[ -n "$UNEXPECTED_BUNDLED_NODES" ]]; then
  echo "error: app Resources/skill contains unexpected payloads" >&2
  find "$BUNDLED_SKILL_ROOT" -mindepth 1 -print >&2
  exit 1
fi
if [[ ! -d "$BUNDLED_SKILL_DIRECTORY" || -L "$BUNDLED_SKILL_DIRECTORY" ]]; then
  echo "error: bundled skill directory is missing or is a symlink" >&2
  exit 1
fi
if find "$BUNDLED_SKILL_ROOT" -type l -print -quit | grep -q .; then
  echo "error: app Resources/skill must not contain symlinks" >&2
  exit 1
fi

CANONICAL_SHA256="$(/usr/bin/shasum -a 256 "$CANONICAL_SKILL" | /usr/bin/awk '{print $1}')"
SWIFTPM_SHA256="$(/usr/bin/shasum -a 256 "$SWIFTPM_SKILL" | /usr/bin/awk '{print $1}')"
BUNDLED_SHA256="$(/usr/bin/shasum -a 256 "$BUNDLED_SKILL" | /usr/bin/awk '{print $1}')"
if [[ "$CANONICAL_SHA256" != "$SWIFTPM_SHA256" ]]; then
  echo "error: SwiftPM assistant skill copy drifted from canonical Resources source" >&2
  echo "  canonical: $CANONICAL_SHA256" >&2
  echo "  SwiftPM:   $SWIFTPM_SHA256" >&2
  exit 1
fi
if [[ "$CANONICAL_SHA256" != "$BUNDLED_SHA256" ]]; then
  echo "error: bundled assistant skill checksum differs from canonical Resources source" >&2
  echo "  canonical: $CANONICAL_SHA256" >&2
  echo "  bundled:   $BUNDLED_SHA256" >&2
  exit 1
fi
echo "ok: SwiftPM skill copy matches canonical sha256 $SWIFTPM_SHA256"
echo "ok: bundled assistant skill sha256 $BUNDLED_SHA256"

if [[ "$DISCOVERY_MODE" != "--exercise-discovery" ]]; then
  exit 0
fi
if [[ ! -x "$BUNDLED_CLI" ]]; then
  echo "error: bundled CLI is unavailable for skill discovery: $BUNDLED_CLI" >&2
  exit 1
fi

# Exercise the real bundled CLI from an isolated app copy and working directory.
# Debug-only checkout fallback is explicitly disabled, so a missing app resource
# cannot be masked by the repository that produced the build.
CONTRACT_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/screenlogger-app-skill.XXXXXX")"
cleanup_skill_contract() {
  rm -rf -- "$CONTRACT_ROOT"
}
trap cleanup_skill_contract EXIT INT TERM

ISOLATED_APP="$CONTRACT_ROOT/Screenlogger.app"
DISCOVERED_SKILLS="$CONTRACT_ROOT/discovered-skills"
WORKING_DIRECTORY="$CONTRACT_ROOT/work"
/usr/bin/ditto "$APP_PATH" "$ISOLATED_APP"
mkdir -p "$DISCOVERED_SKILLS" "$WORKING_DIRECTORY"

(
  cd "$WORKING_DIRECTORY"
  env -u SCREENLOG_SKILL_DIR \
    SCREENLOG_DISABLE_CHECKOUT_SKILL_FALLBACK=1 \
    "$ISOLATED_APP/Contents/MacOS/screenlog" \
    skill install codex --directory "$DISCOVERED_SKILLS" >/dev/null
)

DISCOVERED_SKILL="$DISCOVERED_SKILLS/screenlog-cli-skill/SKILL.md"
if [[ ! -f "$DISCOVERED_SKILL" || -L "$DISCOVERED_SKILL" ]]; then
  echo "error: bundled CLI did not discover and install the app-contained skill" >&2
  exit 1
fi
DISCOVERED_SHA256="$(/usr/bin/shasum -a 256 "$DISCOVERED_SKILL" | /usr/bin/awk '{print $1}')"
if [[ "$DISCOVERED_SHA256" != "$CANONICAL_SHA256" ]]; then
  echo "error: skill discovered by bundled CLI differs from canonical source" >&2
  exit 1
fi
echo "ok: bundled CLI discovered the app-contained skill without checkout fallback"
