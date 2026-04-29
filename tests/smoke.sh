#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
entry="$repo_root/scripts/fixmd.sh"

pass=0
fail=0

check() {
  local label="$1"
  local status="$2"
  if [[ "$status" == "0" ]]; then
    echo "  OK  $label"
    pass=$((pass + 1))
  else
    echo "  FAIL $label"
    fail=$((fail + 1))
  fi
}

contains() {
  local haystack="$1"
  local needle="$2"
  [[ "$haystack" == *"$needle"* ]]
}

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

sample_repo="$tmpdir/sample"
mkdir -p "$sample_repo/docs"
cat >"$sample_repo/docs/ok.md" <<'EOF'
# Sample

Some markdown content.
EOF

help_out="$("$entry" --help)"
if contains "$help_out" "Usage:"; then
  check "help surface" 0
else
  check "help surface" 1
fi

set +e
json_out="$("$entry" --target "$sample_repo" --json 2>&1)"
json_rc=$?
set -e

if [[ "$json_rc" == "0" || "$json_rc" == "1" ]]; then
  check "json command returns expected exit band" 0
else
  check "json command returns expected exit band" 1
fi

if contains "$json_out" '"schema_version": "fixmd/v1"'; then
  check "json schema version" 0
else
  check "json schema version" 1
fi

if contains "$json_out" '"tool": "fixmd"'; then
  check "json tool name" 0
else
  check "json tool name" 1
fi

if contains "$json_out" '"config"'; then
  check "json includes config block" 0
else
  check "json includes config block" 1
fi

if [[ "$fail" -gt 0 ]]; then
  echo
  echo "passed: $pass failed: $fail"
  exit 1
fi

echo
echo "passed: $pass failed: $fail"
