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

check_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"
  if contains "$haystack" "$needle"; then
    check "$label" 0
  else
    check "$label" 1
  fi
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
check_contains "$json_out" '"schema_version": "fixmd/v1"' "json schema version"
check_contains "$json_out" '"tool": "fixmd"' "json tool name"
check_contains "$json_out" '"config"' "json includes config block"
check_contains "$json_out" '"source": "temporary"' "default mode uses temporary config"
check_contains "$json_out" '"kind": "fallback"' "default mode reports fallback kind"

if [[ ! -f "$sample_repo/.markdownlint.jsonc" ]]; then
  check "default mode does not write config" 0
else
  check "default mode does not write config" 1
fi

install_repo="$tmpdir/install-repo"
mkdir -p "$install_repo/docs"
cat >"$install_repo/docs/ok.md" <<'EOF'
# Install Sample

Some markdown content.
EOF

set +e
install_out="$("$entry" --target "$install_repo" --install-config --json 2>&1)"
install_rc=$?
set -e

if [[ "$install_rc" == "0" ]]; then
  check "--install-config succeeds" 0
else
  check "--install-config succeeds" 1
fi

check_contains "$install_out" '"source": "installed"' "--install-config reports installed source"
check_contains "$install_out" '"kind": "markdownlint"' "--install-config reports markdownlint kind"

if [[ -f "$install_repo/.markdownlint.jsonc" ]]; then
  check "--install-config writes config file" 0
else
  check "--install-config writes config file" 1
fi

existing_repo="$tmpdir/existing-repo"
mkdir -p "$existing_repo/docs"
cat >"$existing_repo/.markdownlint.jsonc" <<'EOF'
{ "default": true, "MD041": false }
EOF
cat >"$existing_repo/docs/ok.md" <<'EOF'
# Existing Sample

Some markdown content.
EOF

before_existing_config="$(cat "$existing_repo/.markdownlint.jsonc")"

set +e
existing_out="$("$entry" --target "$existing_repo" --install-config --json 2>&1)"
existing_rc=$?
set -e

if [[ "$existing_rc" == "0" ]]; then
  check "existing config install path succeeds" 0
else
  check "existing config install path succeeds" 1
fi

check_contains "$existing_out" '"source": "existing"' "existing config is preserved"
check_contains "$existing_out" 'skipped --install-config' "existing config skip hint"

after_existing_config="$(cat "$existing_repo/.markdownlint.jsonc")"
if [[ "$before_existing_config" == "$after_existing_config" ]]; then
  check "existing config content unchanged" 0
else
  check "existing config content unchanged" 1
fi

if [[ "$fail" -gt 0 ]]; then
  echo
  echo "passed: $pass failed: $fail"
  exit 1
fi

echo
echo "passed: $pass failed: $fail"
