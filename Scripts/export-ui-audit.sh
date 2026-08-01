#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
OUTPUT="$ROOT/build/ui-audit"

if [[ "$#" -eq 0 ]]; then
  echo "usage: Scripts/export-ui-audit.sh <path-to-Test-*.xcresult> [...]" >&2
  exit 64
fi

for result_bundle in "$@"; do
  if [[ ! -d "$result_bundle" ]]; then
    echo "error: result bundle not found: $result_bundle" >&2
    exit 66
  fi
done

if [[ ! -d "$DEVELOPER_DIR" ]]; then
  echo "error: Xcode developer directory not found: $DEVELOPER_DIR" >&2
  exit 69
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required to curate named visual-audit attachments" >&2
  exit 69
fi

mkdir -p "$ROOT/build"
EXPORT_ROOT="$(mktemp -d "$ROOT/build/ui-audit-export.XXXXXX")"
trap 'rm -rf "$EXPORT_ROOT"' EXIT

mkdir -p "$EXPORT_ROOT/curated"
INDEX="$EXPORT_ROOT/curated/index.tsv"
printf 'attachment\ttest\n' > "$INDEX"

bundle_index=0
for result_bundle in "$@"; do
  raw_output="$EXPORT_ROOT/raw-$bundle_index"
  DEVELOPER_DIR="$DEVELOPER_DIR" xcrun xcresulttool export attachments \
    --path "$result_bundle" \
    --output-path "$raw_output"

  while IFS=$'\t' read -r exported suggested test_identifier; do
    safe_name="$(printf '%s' "$suggested" | tr '/:' '--')"
    cp "$raw_output/$exported" "$EXPORT_ROOT/curated/$safe_name"
    printf '%s\t%s\n' "$safe_name" "$test_identifier" >> "$INDEX"
  done < <(
    jq -r '
      .[]
      | .testIdentifier as $test
      | .attachments[]
      | select(.suggestedHumanReadableName | startswith("ui-audit-"))
      | [.exportedFileName, .suggestedHumanReadableName, $test]
      | @tsv
    ' "$raw_output/manifest.json"
  )
  bundle_index=$((bundle_index + 1))
done

attachment_count="$(($(wc -l < "$INDEX") - 1))"
if [[ "$attachment_count" -eq 0 ]]; then
  echo "error: no named ui-audit attachments were found in the supplied result bundles" >&2
  exit 65
fi

rm -rf "$OUTPUT"
mv "$EXPORT_ROOT/curated" "$OUTPUT"

echo "Exported $attachment_count visual-audit attachments to $OUTPUT"
echo "Open $OUTPUT/index.tsv to map each file to its test."
