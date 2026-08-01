#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/Screenlog.xcodeproj"
DERIVED_DATA="${SCREENLOGGER_UI_DERIVED_DATA:-$ROOT/build/UITestDerivedData}"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
HOST_ARCH="$(uname -m)"

if [[ ! -d "$DEVELOPER_DIR" ]]; then
  echo "error: Xcode developer directory not found: $DEVELOPER_DIR" >&2
  exit 1
fi

# XCUITest launches and terminates the app under test. Never allow that to
# disturb a real menu-bar capture session owned by this user.
RUNNING_PIDS="$(/usr/bin/swift -e '
import AppKit
import Darwin

let pids = NSRunningApplication.runningApplications(withBundleIdentifier: "dev.screenlog.app")
    .map(\.processIdentifier)
    .filter { Darwin.kill($0, 0) == 0 }
print(pids.map(String.init).joined(separator: ","))
')"
if [[ -n "$RUNNING_PIDS" ]]; then
  echo "error: Screenlogger is already running (PID $RUNNING_PIDS); quit it before UI tests" >&2
  exit 2
fi

DEVELOPER_DIR="$DEVELOPER_DIR" xcodebuild \
  -project "$PROJECT" \
  -scheme ScreenlogUI \
  -configuration Debug \
  -destination "platform=macOS,arch=$HOST_ARCH" \
  -derivedDataPath "$DERIVED_DATA" \
  -only-testing:ScreenlogAppUITests \
  -parallel-testing-enabled NO \
  ONLY_ACTIVE_ARCH=YES \
  test
