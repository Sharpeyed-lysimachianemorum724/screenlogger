#!/usr/bin/env bash
# Remove Screenlogger.app + screenlog CLI installed by Scripts/install.sh.
#
# By default keeps local data and assistant integrations.
#   --purge-data   also delete ~/Library/Application Support/dev.screenlog
#   --purge-skills remove authenticated screenlog-cli-skill integrations
#
# Overrides match install.sh:
#   SCREENLOG_PREFIX   app install dir (default: ~/Applications)
#   SCREENLOG_BIN      CLI install dir (default: ~/.local/bin)
#   SCREENLOG_HOME     home used for integration/data paths (test/managed installs)
set -euo pipefail

USER_HOME="${SCREENLOG_HOME:-$HOME}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=Scripts/lib/install-lifecycle.sh
source "$ROOT/Scripts/lib/install-lifecycle.sh"
if [[ "$USER_HOME" != /* || "$USER_HOME" == "/" || "$USER_HOME" == *$'\n'* || ! -d "$USER_HOME" ]]; then
  echo "error: SCREENLOG_HOME must identify an existing, absolute, non-root directory" >&2
  exit 1
fi
USER_HOME="$(cd "$USER_HOME" && pwd -P)"
PREFIX="${SCREENLOG_PREFIX:-$USER_HOME/Applications}"
BIN_DIR="${SCREENLOG_BIN:-$USER_HOME/.local/bin}"
if ! sl_validate_install_roots "$PREFIX" "$BIN_DIR"; then
  echo "error: uninstall destinations must be absolute, non-root paths without newlines or dot-segments" >&2
  exit 1
fi
PREFIX="$(sl_resolve_install_root "$PREFIX")" || {
  echo "error: app install root does not resolve to a safe non-root directory" >&2
  exit 1
}
BIN_DIR="$(sl_resolve_install_root "$BIN_DIR")" || {
  echo "error: CLI install root does not resolve to a safe non-root directory" >&2
  exit 1
}
if ! sl_validate_install_roots "$PREFIX" "$BIN_DIR"; then
  echo "error: resolved uninstall destinations are not safe non-root directories" >&2
  exit 1
fi
APP_DST="$PREFIX/Screenlogger.app"
CLI_DST="$BIN_DIR/screenlog"
DATA_DIR="${USER_HOME}/Library/Application Support/dev.screenlog"
CACHE_DIR="$USER_HOME/Library/Caches/dev.screenlog"
APP_CACHE_DIR="$USER_HOME/Library/Caches/dev.screenlog.app"
PREFERENCES_FILE="$USER_HOME/Library/Preferences/dev.screenlog.app.plist"
HTTP_STORAGE_DIR="$USER_HOME/Library/HTTPStorages/dev.screenlog.app"
SAVED_STATE_DIR="$USER_HOME/Library/Saved Application State/dev.screenlog.app.savedState"
LOCAL_RECEIPT="$PREFIX/$SL_RECEIPT_NAME"

PURGE_DATA=0
PURGE_SKILLS=0
for arg in "$@"; do
  case "$arg" in
    --purge-data) PURGE_DATA=1 ;;
    --purge-skills) PURGE_SKILLS=1 ;;
    -h|--help)
      cat <<EOF
Usage: $(basename "$0") [--purge-data] [--purge-skills]

Removes the app and authenticated command-line artifacts:
  $APP_DST
  $CLI_DST
  $BIN_DIR/ScreenlogCore.framework
  $BIN_DIR/Frameworks/ScreenlogCore.framework

Options:
  --purge-data     Delete recordings, SQLite, preferences, and app caches under
                   this user's Library. Does not remove system crash reports.
  --purge-skills   Remove only authenticated Screenlogger assistant integrations.
                   Unrelated files, broken links, and ambiguous paths are preserved.
EOF
      exit 0
      ;;
    *)
      echo "unknown option: $arg (try --help)" >&2
      exit 1
      ;;
  esac
done

echo "==> Uninstalling Screenlogger..."

remove_path() {
  local p="$1"
  if [[ -e "$p" || -L "$p" ]]; then
    echo "  rm  $p"
    rm -rf "$p"
  else
    echo "  skip (missing) $p"
  fi
}

skill_is_screenlogger_owned() {
  local path="$1"
  local manifest="$path/SKILL.md"
  local byte_count
  [[ -d "$path" && -f "$manifest" && ! -L "$manifest" ]] || return 1
  byte_count="$(wc -c < "$manifest" 2>/dev/null)" || return 1
  [[ "$byte_count" -le 1048576 ]] || return 1
  head -n 12 "$manifest" | awk '
    {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      sub(/[[:space:]]+$/, "", line)
      if (line == "name: screenlog-cli-skill") found = 1
    }
    END { exit(found ? 0 : 1) }
  '
}

remove_owned_skill() {
  local path="$1"
  if [[ ! -e "$path" && ! -L "$path" ]]; then
    echo "  skip (missing) $path"
  elif skill_is_screenlogger_owned "$path"; then
    remove_path "$path"
  else
    echo "  preserve (not authenticated as Screenlogger-owned) $path" >&2
  fi
}

framework_is_screenlogger_owned() {
  local framework="$1"
  local info=""
  local identifier=""
  [[ -d "$framework" && ! -L "$framework" ]] || return 1
  if [[ -f "$framework/Versions/A/Resources/Info.plist" ]]; then
    info="$framework/Versions/A/Resources/Info.plist"
  elif [[ -f "$framework/Resources/Info.plist" ]]; then
    info="$framework/Resources/Info.plist"
  else
    return 1
  fi
  identifier="$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$info" 2>/dev/null || true)"
  [[ "$identifier" == "dev.screenlog.core" ]] || return 1
}

cli_pair_is_screenlogger_owned() {
  [[ -f "$CLI_DST" && -x "$CLI_DST" && ! -L "$CLI_DST" ]] || return 1
  if ! framework_is_screenlogger_owned "$BIN_DIR/ScreenlogCore.framework" \
    && ! framework_is_screenlogger_owned "$BIN_DIR/Frameworks/ScreenlogCore.framework"; then
    return 1
  fi
  /usr/bin/otool -L "$CLI_DST" 2>/dev/null \
    | grep -Fq '@rpath/ScreenlogCore.framework/Versions/A/ScreenlogCore'
}

receipt_is_screenlogger_owned() {
  local receipt="$BIN_DIR/.screenlog-cli-install.json"
  local product=""
  [[ -f "$receipt" && ! -L "$receipt" ]] || return 1
  product="$(/usr/bin/plutil -extract productIdentifier raw -o - "$receipt" 2>/dev/null || true)"
  [[ "$product" == "dev.screenlog.cli" ]]
}

CLI_OWNED=0
APP_OWNED=0
LOCAL_INSTALL_OWNED=0
if sl_node_exists "$LOCAL_RECEIPT"; then
  if sl_receipt_matches "$LOCAL_RECEIPT" "$APP_DST" "$CLI_DST" "$BIN_DIR/ScreenlogCore.framework"; then
    LOCAL_INSTALL_OWNED=1
    APP_OWNED=1
    CLI_OWNED=1
  else
    echo "  preserve: local-install receipt or artifacts were modified; app and CLI require manual review" >&2
  fi
else
  # Narrow migration path for installs made by older repository scripts.
  if sl_node_exists "$APP_DST" && sl_app_recognized "$APP_DST"; then
    APP_OWNED=1
  fi
fi
if [[ "$LOCAL_INSTALL_OWNED" -ne 1 ]] && ! sl_node_exists "$LOCAL_RECEIPT" && cli_pair_is_screenlogger_owned; then
  CLI_OWNED=1
fi
CLI_CAN_MANAGE_SKILLS=0
if [[ "$CLI_OWNED" -eq 1 && "$USER_HOME" == "$HOME" ]]; then
  CLI_CAN_MANAGE_SKILLS=1
fi

if [[ "$PURGE_SKILLS" -eq 1 ]]; then
  echo "==> Removing authenticated assistant integrations..."
  # Let the still-installed, authenticated CLI remove OpenClaw registration and
  # apply the same ownership rules as Settings. Shell checks below are a safe
  # fallback if an older CLI cannot launch.
  if [[ "$CLI_CAN_MANAGE_SKILLS" -eq 1 ]]; then
    for target in claude cursor codex grok openclaw; do
      if ! "$CLI_DST" skill remove "$target" >/dev/null 2>&1; then
        echo "  note: CLI could not fully remove $target; checking its files safely" >&2
      fi
    done
  fi
  for d in \
    "$USER_HOME/.claude/skills/screenlog-cli-skill" \
    "$USER_HOME/.agents/skills/screenlog-cli-skill" \
    "$USER_HOME/.codex/skills/screenlog-cli-skill" \
    "$USER_HOME/.cursor/skills/screenlog-cli-skill" \
    "$USER_HOME/.grok/skills/screenlog-cli-skill" \
    "$USER_HOME/Library/Application Support/dev.screenlog/skill/screenlog-cli-skill"
  do
    remove_owned_skill "$d"
  done
  if [[ "$CLI_CAN_MANAGE_SKILLS" -ne 1 ]]; then
    echo "  note: OpenClaw configuration was preserved because no authenticated screenlog CLI was available." >&2
  fi
fi

if ! sl_node_exists "$APP_DST"; then
  echo "  skip (missing) $APP_DST"
elif [[ "$APP_OWNED" -eq 1 ]]; then
  remove_path "$APP_DST"
else
  echo "  preserve (app is not authenticated as Screenlogger-owned) $APP_DST" >&2
fi

if [[ "$CLI_OWNED" -eq 1 ]]; then
  remove_path "$CLI_DST"
  for framework in \
    "$BIN_DIR/ScreenlogCore.framework" \
    "$BIN_DIR/Frameworks/ScreenlogCore.framework"
  do
    if [[ ! -e "$framework" && ! -L "$framework" ]]; then
      echo "  skip (missing) $framework"
    elif framework_is_screenlogger_owned "$framework"; then
      remove_path "$framework"
    else
      echo "  preserve (framework is not authenticated as Screenlogger-owned) $framework" >&2
    fi
  done
  if [[ ! -e "$BIN_DIR/.screenlog-cli-install.json" && ! -L "$BIN_DIR/.screenlog-cli-install.json" ]]; then
    echo "  skip (missing) $BIN_DIR/.screenlog-cli-install.json"
  elif receipt_is_screenlogger_owned; then
    remove_path "$BIN_DIR/.screenlog-cli-install.json"
  else
    echo "  preserve (receipt is not authenticated as Screenlogger-owned) $BIN_DIR/.screenlog-cli-install.json" >&2
  fi
  remove_owned_skill "$BIN_DIR/skill/screenlog-cli-skill"
else
  for path in \
    "$CLI_DST" \
    "$BIN_DIR/ScreenlogCore.framework" \
    "$BIN_DIR/Frameworks/ScreenlogCore.framework" \
    "$BIN_DIR/.screenlog-cli-install.json" \
    "$BIN_DIR/skill/screenlog-cli-skill"
  do
    if [[ -e "$path" || -L "$path" ]]; then
      echo "  preserve (CLI installation is incomplete or not authenticated) $path" >&2
    fi
  done
fi

if [[ "$LOCAL_INSTALL_OWNED" -eq 1 ]]; then
  remove_path "$LOCAL_RECEIPT"
elif sl_node_exists "$LOCAL_RECEIPT"; then
  echo "  preserve (local-install receipt is invalid or no longer matches) $LOCAL_RECEIPT" >&2
fi

if [[ -d "$BIN_DIR/skill" ]] && [[ -z "$(ls -A "$BIN_DIR/skill" 2>/dev/null || true)" ]]; then
  rmdir "$BIN_DIR/skill" 2>/dev/null || true
fi

# Drop empty Frameworks dir if we emptied it.
if [[ -d "$BIN_DIR/Frameworks" ]] && [[ -z "$(ls -A "$BIN_DIR/Frameworks" 2>/dev/null || true)" ]]; then
  rmdir "$BIN_DIR/Frameworks" 2>/dev/null || true
fi

if [[ "$PURGE_DATA" -eq 1 ]]; then
  echo "==> Purging Screenlogger data, preferences, and caches..."
  for local_data_path in \
    "$DATA_DIR" \
    "$CACHE_DIR" \
    "$APP_CACHE_DIR" \
    "$PREFERENCES_FILE" \
    "$HTTP_STORAGE_DIR" \
    "$SAVED_STATE_DIR"
  do
    remove_path "$local_data_path"
  done
else
  if [[ -d "$DATA_DIR" ]]; then
    echo "==> Keeping data at: $DATA_DIR"
    echo "    (pass --purge-data to delete recordings / SQLite)"
  fi
fi

echo "Done."
