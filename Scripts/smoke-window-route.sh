#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$ROOT/build/DerivedData/Build/Products/Debug/Screenlogger.app}"
if [[ "$APP" != /* ]]; then
  APP="$PWD/$APP"
fi
ROUTE="${2:-library}"
EXECUTABLE="$APP/Contents/MacOS/Screenlogger"

case "$ROUTE" in
  library)
    ROUTE_ARGUMENT="--open-library"
    EXPECTED_WINDOW_TITLE="Library"
    ;;
  timeline)
    ROUTE_ARGUMENT="--open-timeline"
    EXPECTED_WINDOW_TITLE="Timeline"
    ;;
  setup)
    ROUTE_ARGUMENT="--open-setup"
    EXPECTED_WINDOW_TITLE="Permissions & Privacy"
    ;;
  reopen)
    ROUTE_ARGUMENT=""
    EXPECTED_WINDOW_TITLE="Library"
    ;;
  *)
    echo "usage: $0 [Screenlogger.app] [library|timeline|setup|reopen]" >&2
    exit 2
    ;;
esac

if [[ ! -x "$EXECUTABLE" ]]; then
  echo "error: Screenlogger executable is missing from $APP" >&2
  exit 1
fi

# Never disturb a user's running product process. Query by bundle ID so this
# also catches an installed app or an older binary with a different filename.
EXISTING_PRODUCT_PIDS="$(/usr/bin/swift -e '
import AppKit
import Darwin

let pids = NSRunningApplication.runningApplications(withBundleIdentifier: "dev.screenlog.app")
    .map(\.processIdentifier)
    .filter { Darwin.kill($0, 0) == 0 }
print(pids.map(String.init).joined(separator: ","))
')"
if [[ -n "$EXISTING_PRODUCT_PIDS" ]]; then
  echo "error: Screenlogger is already running (PID $EXISTING_PRODUCT_PIDS); quit it before this smoke test" >&2
  exit 2
fi

# Every PID terminated below either comes from `$!` or carries this
# invocation's unguessable token.

SMOKE_DATA="$(mktemp -d "${TMPDIR:-/tmp}/screenlogger-window-route.XXXXXX")"
SMOKE_TOKEN="$(uuidgen)"
DIRECT_TOKEN="$SMOKE_TOKEN-direct"
BASE_TOKEN="$SMOKE_TOKEN-base"
RELAY_TOKEN="$SMOKE_TOKEN-relay"
VISIBLE_BASE_TOKEN="$SMOKE_TOKEN-visible-base"
VISIBLE_REOPEN_TOKEN="$SMOKE_TOKEN-visible-reopen"
SMOKE_HOME="$SMOKE_DATA/home"
OWNED_PIDS=()

# Keep both product data and preferences out of the user's real Screenlogger
# installation. The base process uses a Debug-only smoke gate below so a fresh
# preference home remains windowless until the test relays an intent.
mkdir -p "$SMOKE_HOME/Library/Preferences"

stop_owned_pid() {
  local pid="$1"
  if kill -0 "$pid" 2>/dev/null; then
    kill -TERM "$pid" 2>/dev/null || true
    for _ in {1..20}; do
      kill -0 "$pid" 2>/dev/null || return 0
      sleep 0.05
    done
    kill -KILL "$pid" 2>/dev/null || true
  fi
}

cleanup() {
  local pid command
  for pid in "${OWNED_PIDS[@]}"; do
    stop_owned_pid "$pid"
  done
  # The `open`-launched relay normally exits immediately. If the assertion
  # fails, only clean up a process carrying this smoke run's unique token.
  for pid in $(pgrep -f "$SMOKE_TOKEN" 2>/dev/null || true); do
    command="$(ps -p "$pid" -o command= 2>/dev/null || true)"
    if [[ "$command" == "$EXECUTABLE"* && "$command" == *"$SMOKE_TOKEN"* ]]; then
      stop_owned_pid "$pid"
    fi
  done
  rm -rf "$SMOKE_DATA"
}
trap cleanup EXIT INT TERM

window_count() {
  local title="${2:-$EXPECTED_WINDOW_TITLE}"
  /usr/bin/swift -e '
import Foundation
import CoreGraphics

let targetPID = Int32(CommandLine.arguments[1])!
let expectedTitle = CommandLine.arguments[2]
let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
let count = windows.filter {
    ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == targetPID &&
        ($0[kCGWindowName as String] as? String) == expectedTitle
}.count
print(count)
' "$1" "$title"
}

assert_window() {
  local phase="$1" pid="$2" title="${3:-$EXPECTED_WINDOW_TITLE}" count
  sleep 1
  if ! kill -0 "$pid" 2>/dev/null; then
    echo "error: $phase process $pid exited before showing its window" >&2
    exit 1
  fi
  count="$(window_count "$pid" "$title")"
  if [[ "$count" -lt 1 ]]; then
    echo "error: $phase produced no on-screen '$title' window for PID $pid" >&2
    exit 1
  fi
  echo "window route smoke passed: phase=$phase route=$ROUTE pid=$pid title='$title' windows=$count"
}

assert_no_window() {
  local phase="$1" pid="$2" title="$3" count
  count="$(window_count "$pid" "$title")"
  if [[ "$count" -ne 0 ]]; then
    echo "error: $phase unexpectedly opened '$title' for PID $pid" >&2
    exit 1
  fi
}

find_tagged_pid() {
  local token="$1" pid="" command=""
  for _ in {1..40}; do
    for pid in $(pgrep -f "$token" 2>/dev/null || true); do
      command="$(ps -p "$pid" -o command= 2>/dev/null || true)"
      if [[ "$command" == "$EXECUTABLE"* && "$command" == *"$token"* ]]; then
        echo "$pid"
        return 0
      fi
    done
    sleep 0.1
  done
  return 1
}

tagged_app_pid() {
  local token="$1" pid command
  for pid in $(pgrep -f "$token" 2>/dev/null || true); do
    command="$(ps -p "$pid" -o command= 2>/dev/null || true)"
    if [[ "$command" == "$EXECUTABLE"* && "$command" == *"$token"* ]]; then
      echo "$pid"
      return 0
    fi
  done
  return 1
}

# Phase 1: an explicit route on the first process must show before bootstrap.
# Reopen has no public launch argument and is therefore relay-only.
if [[ "$ROUTE" != "reopen" ]]; then
  mkdir -p "$SMOKE_DATA/direct"
  open -na "$APP" --env "SCREENLOG_DATA_DIR=$SMOKE_DATA/direct" \
    --env "CFFIXED_USER_HOME=$SMOKE_HOME" \
    --args "$ROUTE_ARGUMENT" --screenlogger-smoke-token "$DIRECT_TOKEN"
  DIRECT_PID="$(find_tagged_pid "$DIRECT_TOKEN")" || {
    echo "error: direct route process did not launch" >&2
    exit 1
  }
  OWNED_PIDS+=("$DIRECT_PID")
  assert_window "direct" "$DIRECT_PID"
  stop_owned_pid "$DIRECT_PID"
fi

# Phase 2: `open -na` must relay the route to an existing windowless process,
# preserve its PID, and let the short-lived route process terminate.
mkdir -p "$SMOKE_DATA/relay"
open -na "$APP" --env "SCREENLOG_DATA_DIR=$SMOKE_DATA/relay" \
  --env "CFFIXED_USER_HOME=$SMOKE_HOME" \
  --env "SCREENLOG_WINDOW_ROUTE_SMOKE=windowless-v1" \
  --args --screenlogger-smoke-token "$BASE_TOKEN"
BASE_PID="$(find_tagged_pid "$BASE_TOKEN")" || {
  echo "error: base relay process did not launch" >&2
  exit 1
}
OWNED_PIDS+=("$BASE_PID")
sleep 0.5
if ! kill -0 "$BASE_PID" 2>/dev/null; then
  echo "error: base relay process $BASE_PID exited during launch" >&2
  exit 1
fi

RELAY_ARGUMENTS=(--screenlogger-smoke-token "$RELAY_TOKEN")
if [[ -n "$ROUTE_ARGUMENT" ]]; then
  RELAY_ARGUMENTS=("$ROUTE_ARGUMENT" "${RELAY_ARGUMENTS[@]}")
fi
open -na "$APP" --env "SCREENLOG_DATA_DIR=$SMOKE_DATA/relay" \
  --env "CFFIXED_USER_HOME=$SMOKE_HOME" \
  --args "${RELAY_ARGUMENTS[@]}"
assert_window "relay" "$BASE_PID"

for _ in {1..30}; do
  RELAY_PID="$(tagged_app_pid "$RELAY_TOKEN" || true)"
  [[ -z "$RELAY_PID" ]] && break
  sleep 0.1
done
if [[ -n "${RELAY_PID:-}" ]]; then
  echo "error: route process $RELAY_PID did not yield to base PID $BASE_PID" >&2
  exit 1
fi

# Phase 3: an unqualified second invocation may activate a visible workflow,
# but must not replace it with Library. This is the no-steal half of the native
# reopen contract and only applies to the internal reopen intent.
if [[ "$ROUTE" == "reopen" ]]; then
  stop_owned_pid "$BASE_PID"
  mkdir -p "$SMOKE_DATA/visible"
  open -na "$APP" --env "SCREENLOG_DATA_DIR=$SMOKE_DATA/visible" \
    --env "CFFIXED_USER_HOME=$SMOKE_HOME" \
    --args --open-timeline --screenlogger-smoke-token "$VISIBLE_BASE_TOKEN"
  VISIBLE_BASE_PID="$(find_tagged_pid "$VISIBLE_BASE_TOKEN")" || {
    echo "error: visible-workflow base process did not launch" >&2
    exit 1
  }
  OWNED_PIDS+=("$VISIBLE_BASE_PID")
  assert_window "visible workflow before reopen" "$VISIBLE_BASE_PID" "Timeline"

  open -na "$APP" --env "SCREENLOG_DATA_DIR=$SMOKE_DATA/visible" \
    --env "CFFIXED_USER_HOME=$SMOKE_HOME" \
    --args --screenlogger-smoke-token "$VISIBLE_REOPEN_TOKEN"
  assert_window "visible workflow after reopen" "$VISIBLE_BASE_PID" "Timeline"
  assert_no_window "visible workflow after reopen" "$VISIBLE_BASE_PID" "Library"

  for _ in {1..30}; do
    VISIBLE_REOPEN_PID="$(tagged_app_pid "$VISIBLE_REOPEN_TOKEN" || true)"
    [[ -z "$VISIBLE_REOPEN_PID" ]] && break
    sleep 0.1
  done
  if [[ -n "${VISIBLE_REOPEN_PID:-}" ]]; then
    echo "error: reopen process $VISIBLE_REOPEN_PID did not yield to visible PID $VISIBLE_BASE_PID" >&2
    exit 1
  fi
fi
