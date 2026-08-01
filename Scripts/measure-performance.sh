#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
XCODE_DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
DEFAULT_OUTPUT="$REPO_ROOT/build/performance/latest.json"
ARGS=("$@")

has_output=false
for argument in "${ARGS[@]}"; do
    if [[ "$argument" == "--output" ]]; then
        has_output=true
        break
    fi
done

if [[ "$has_output" == false ]]; then
    ARGS+=(--output "$DEFAULT_OUTPUT")
fi

cd "$REPO_ROOT"
DEVELOPER_DIR="$XCODE_DEVELOPER_DIR" swift run -c release screenlog-performance "${ARGS[@]}"
