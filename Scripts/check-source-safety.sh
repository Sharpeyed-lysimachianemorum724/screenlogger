#!/usr/bin/env bash
set -euo pipefail

REPOSITORY_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPOSITORY_ROOT"

# Production paths must return typed failures or use an explicit recovery path.
# Forced casts, forced-try expressions, and fatal traps turn malformed input
# or a future refactor into a process crash.
safety_pattern='(^|[^[:alnum:]_])(try|as)!|(^|[^[:alnum:]_])fatalError[[:space:]]*\(|(^|[^[:alnum:]_])preconditionFailure[[:space:]]*\('
if command -v rg >/dev/null 2>&1; then
  matches="$(rg -n --glob '*.swift' "$safety_pattern" Sources || true)"
else
  # Git is guaranteed in CI. Do not silently pass when an optional search
  # utility is absent from a hosted runner image.
  matches="$(git grep -n -I -E "$safety_pattern" -- 'Sources/**/*.swift' || true)"
fi

if [[ -n "$matches" ]]; then
  echo "error: forced Swift failure path found in Sources:" >&2
  echo "$matches" >&2
  exit 1
fi

# Permission status is polled by menu, setup, and activation flows. It must
# never perform real ScreenCaptureKit access, which can surface repeated macOS
# privacy notifications. Capture APIs belong only to explicit capture work.
permission_status_file="Sources/ScreenlogCore/Permissions/PermissionStatus.swift"
if command -v rg >/dev/null 2>&1; then
  permission_probe_matches="$(rg -n '^import ScreenCaptureKit|SCShareableContent\.' "$permission_status_file" || true)"
else
  permission_probe_matches="$(git grep -n -E '^import ScreenCaptureKit|SCShareableContent\.' -- "$permission_status_file" || true)"
fi
if [[ -n "$permission_probe_matches" ]]; then
  echo "error: permission status performs ScreenCaptureKit access:" >&2
  echo "$permission_probe_matches" >&2
  exit 1
fi

echo "source safety: passed"
