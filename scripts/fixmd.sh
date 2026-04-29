#!/usr/bin/env bash
set -euo pipefail

EXIT_OK=0
EXIT_CHECK_FAILED=1
EXIT_INVALID_INPUT=2
EXIT_TOOL_UNAVAILABLE=4

usage() {
    cat <<'USAGE'
Usage:
  fixmd.sh --target <repo-root> [--json] [--install-config]

Options:
  --target <dir>     Repository root to scan.
  --json             Emit JSON output.
  --install-config   Install .markdownlint.jsonc at repo root only when the repo has no markdownlint config.
  -h, --help         Show this help.
USAGE
}

skill_root() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    cd "$script_dir/.." && pwd
}

json_escape() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\n'/\\n}"
    value="${value//$'\r'/\\r}"
    value="${value//$'\t'/\\t}"
    printf '%s' "$value"
}

json_array() {
    local first=1
    local item=""
    printf '['
    for item in "$@"; do
        if [[ "$first" -eq 0 ]]; then
            printf ','
        fi
        first=0
        printf '"%s"' "$(json_escape "$item")"
    done
    printf ']'
}

first_line() {
    local text="$1"
    text="${text%%$'\n'*}"
    printf '%s' "$text"
}

add_hint() {
    local value="$1"
    local item=""
    [[ -n "$value" ]] || return 0
    for item in "${hints[@]}"; do
        if [[ "$item" == "$value" ]]; then
            return 0
        fi
    done
    hints+=("$value")
}

append_markdownlint_failures() {
    local raw="$1"
    local parsed line files
    parsed="$(printf '%s\n' "$raw" | awk '
        /:[0-9]+(:[0-9]+)?[[:space:]]+error[[:space:]]+MD[0-9]+\/[^[:space:]]+/ {
            print
            count++
            if (count >= 5) {
                exit
            }
        }
    ')"

    if [[ -n "$parsed" ]]; then
        while IFS= read -r line; do
            [[ -n "$line" ]] || continue
            failures+=("markdownlint: $line")
        done <<<"$parsed"
        files="$(printf '%s\n' "$parsed" | awk '
            {
                if (match($0, /:[0-9]+(:[0-9]+)?[[:space:]]+error[[:space:]]+MD[0-9]+\//)) {
                    print substr($0, 1, RSTART - 1)
                } else {
                    print $0
                }
            }
        ' | sort -u | paste -sd ', ' -)"
        if [[ -n "$files" ]]; then
            add_hint "fix markdownlint issues in: $files"
        fi
        add_hint "run markdownlint-cli2 <file> (or markdownlint <file>) for full diagnostics"
        return 0
    fi

    line="$(first_line "$raw")"
    if [[ -z "$line" ]]; then
        line="markdownlint check failed"
    fi
    failures+=("markdownlint: $line")
}

emit_json() {
    local hints_json failures_json error_json
    hints_json="$(json_array "${hints[@]}")"
    failures_json="$(json_array "${failures[@]}")"
    if [[ -z "$error_code" ]]; then
        error_json="null"
    else
        error_json="{\"code\":\"$(json_escape "$error_code")\",\"message\":\"$(json_escape "$error_message")\"}"
    fi
    cat <<EOF_JSON
{
  "schema_version": "$schema_version",
  "tool": "$tool_name",
  "status": "$status",
  "data": {
    "target_root": "$(json_escape "$target_root")",
    "files_total": $files_total,
    "config": {
      "source": "$config_source",
      "kind": "$config_kind"
    },
    "fix": {
      "applied": $fix_applied,
      "needs_agent_refine": $needs_agent_refine
    },
    "checks": {
      "markdownlint": {"status": "$markdownlint_status", "toolchain": "$toolchain_markdownlint"}
    },
    "hints": $hints_json,
    "failures": $failures_json
  },
  "error": $error_json
}
EOF_JSON
}

emit_text() {
    local result_word="PASS"
    local item=""
    if [[ "$status" != "ok" ]]; then
        result_word="FAIL"
    fi

    echo "# fixmd report"
    echo
    echo "## Summary"
    echo "- result: $result_word"
    echo "- target_root: $target_root"
    echo "- files_total: $files_total"
    echo "- config: $config_source/$config_kind"
    echo "- fix_applied: $fix_applied"
    echo "- needs_agent_refine: $needs_agent_refine"
    echo "- markdownlint: $markdownlint_status (toolchain=$toolchain_markdownlint)"
    if [[ -n "$error_code" ]]; then
        echo "- error_code: $error_code"
        echo "- error_message: $error_message"
    fi

    echo
    echo "## Failures"
    if [[ "${#failures[@]}" -eq 0 ]]; then
        echo "- none"
    else
        for item in "${failures[@]}"; do
            echo "- $item"
        done
    fi

    echo
    echo "## Next"
    if [[ "${#hints[@]}" -eq 0 ]]; then
        echo "- none"
    else
        for item in "${hints[@]}"; do
            echo "- $item"
        done
    fi
}

emit_output() {
    if [[ "$json_out" == "true" ]]; then
        emit_json
    else
        emit_text
    fi
}

exit_with_status() {
    if [[ "$status" != "ok" ]]; then
        if [[ "$error_code" == "tool_unavailable" ]]; then
            exit "$EXIT_TOOL_UNAVAILABLE"
        fi
        exit "$EXIT_CHECK_FAILED"
    fi
    exit "$EXIT_OK"
}

cleanup() {
    if [[ -n "$temp_config_dir" && -d "$temp_config_dir" ]]; then
        rm -rf "$temp_config_dir"
    fi
}

load_template_path() {
    local skill_dir
    skill_dir="$(skill_root)"
    template_path="$skill_dir/assets/markdownlint.agent.jsonc"
    if [[ ! -f "$template_path" ]]; then
        echo "[ERROR] missing markdownlint template: $template_path" >&2
        return "$EXIT_INVALID_INPUT"
    fi
    return 0
}

has_package_json_markdownlint_cli2_config() {
    local package_json="$1"
    local rc=1
    [[ -f "$package_json" ]] || return 1

    if command -v python3 >/dev/null 2>&1; then
        set +e
        python3 - "$package_json" <<'PY'
import json
import sys
try:
    with open(sys.argv[1], 'r', encoding='utf-8') as handle:
        payload = json.load(handle)
except Exception:
    raise SystemExit(2)
raise SystemExit(0 if payload.get('markdownlint-cli2') is not None else 1)
PY
        rc=$?
        set -e
    elif command -v node >/dev/null 2>&1; then
        set +e
        node -e 'const fs = require("fs"); try { const payload = JSON.parse(fs.readFileSync(process.argv[1], "utf8")); process.exit(payload["markdownlint-cli2"] !== undefined ? 0 : 1); } catch { process.exit(2); }' "$package_json"
        rc=$?
        set -e
    else
        return 1
    fi

    if [[ "$rc" -eq 2 ]]; then
        add_hint "package.json exists but markdownlint-cli2 config could not be parsed; skipped package.json detection"
        return 1
    fi
    return "$rc"
}

set_config_mode() {
    local source="$1"
    local kind="$2"
    local mode="$3"
    local path_value="$4"
    local supports_cli2="$5"
    local supports_markdownlint="$6"

    config_source="$source"
    config_kind="$kind"
    config_mode="$mode"
    markdownlint_config="$path_value"
    config_supports_cli2="$supports_cli2"
    config_supports_markdownlint="$supports_markdownlint"
}

install_markdownlint_config() {
    local root_cfg="$target_root/.markdownlint.jsonc"
    load_template_path || return "$EXIT_INVALID_INPUT"
    if ! cp "$template_path" "$root_cfg"; then
        echo "[ERROR] failed to install markdownlint config: $root_cfg" >&2
        return "$EXIT_INVALID_INPUT"
    fi
    set_config_mode "installed" "markdownlint" "explicit" "$root_cfg" "true" "true"
    add_hint "installed .markdownlint.jsonc at repo root; review and commit it if you want a shared baseline"
    return 0
}

prepare_temporary_markdownlint_config() {
    load_template_path || return "$EXIT_INVALID_INPUT"
    temp_config_dir="$(mktemp -d "${TMPDIR:-/tmp}/fixmd.XXXXXX")"
    if [[ -z "$temp_config_dir" || ! -d "$temp_config_dir" ]]; then
        echo "[ERROR] failed to create temporary directory for markdownlint config" >&2
        return "$EXIT_INVALID_INPUT"
    fi
    if ! cp "$template_path" "$temp_config_dir/.markdownlint.jsonc"; then
        echo "[ERROR] failed to prepare temporary markdownlint config" >&2
        return "$EXIT_INVALID_INPUT"
    fi
    set_config_mode "temporary" "fallback" "explicit" "$temp_config_dir/.markdownlint.jsonc" "true" "true"
    add_hint "repo has no markdownlint config; used temporary fixmd baseline without writing repo files"
    return 0
}

resolve_markdownlint_config() {
    local candidate=""
    local package_json="$target_root/package.json"

    for candidate in \
        "$target_root/.markdownlint-cli2.jsonc" \
        "$target_root/.markdownlint-cli2.yaml" \
        "$target_root/.markdownlint-cli2.cjs" \
        "$target_root/.markdownlint-cli2.mjs"; do
        if [[ -f "$candidate" ]]; then
            set_config_mode "existing" "markdownlint-cli2" "auto" "$candidate" "true" "false"
            return 0
        fi
    done

    if has_package_json_markdownlint_cli2_config "$package_json"; then
        set_config_mode "existing" "package-json" "auto" "$package_json" "true" "false"
        return 0
    fi

    for candidate in \
        "$target_root/.markdownlint.jsonc" \
        "$target_root/.markdownlint.json" \
        "$target_root/.markdownlint.yaml" \
        "$target_root/.markdownlint.yml" \
        "$target_root/.markdownlint.cjs" \
        "$target_root/.markdownlint.mjs"; do
        if [[ -f "$candidate" ]]; then
            if [[ "$candidate" == *.mjs ]]; then
                set_config_mode "existing" "markdownlint" "explicit" "$candidate" "true" "false"
            else
                set_config_mode "existing" "markdownlint" "explicit" "$candidate" "true" "true"
            fi
            return 0
        fi
    done

    if [[ -f "$target_root/.markdownlintrc" ]]; then
        set_config_mode "existing" "legacy-rc" "auto" "$target_root/.markdownlintrc" "false" "true"
        add_hint "legacy .markdownlintrc detected; migrate to .markdownlint.jsonc for repo-local deterministic behavior"
        return 0
    fi

    if [[ "$install_config" == "true" ]]; then
        install_markdownlint_config
        return $?
    fi

    prepare_temporary_markdownlint_config
    return $?
}

choose_markdownlint_cmd() {
    if [[ "$config_supports_cli2" == "true" && "$config_supports_markdownlint" == "false" ]]; then
        if [[ "$has_cli2" == "true" ]]; then
            markdownlint_cmd="markdownlint-cli2"
            toolchain_markdownlint="local"
            return 0
        fi
        if [[ "$config_kind" == "markdownlint" ]]; then
            failures+=("markdownlint-cli2 required by detected repo config")
            add_hint "repo config uses a CLI2-only format; install markdownlint-cli2 locally or migrate to .markdownlint.jsonc/.cjs"
        else
            failures+=("markdownlint-cli2 required by detected repo config")
            add_hint "repo config requires markdownlint-cli2; install it locally or migrate to a .markdownlint.* config"
        fi
        return 127
    fi

    if [[ "$config_supports_markdownlint" == "true" && "$config_supports_cli2" == "false" ]]; then
        if [[ "$has_markdownlint" == "true" ]]; then
            markdownlint_cmd="markdownlint"
            toolchain_markdownlint="local"
            return 0
        fi
        failures+=("markdownlint CLI required by detected repo config")
        add_hint "install markdownlint locally or migrate .markdownlintrc to .markdownlint.jsonc"
        return 127
    fi

    if [[ "$has_cli2" == "true" ]]; then
        markdownlint_cmd="markdownlint-cli2"
        toolchain_markdownlint="local"
        return 0
    fi
    if [[ "$has_markdownlint" == "true" ]]; then
        markdownlint_cmd="markdownlint"
        toolchain_markdownlint="local"
        return 0
    fi

    failures+=("markdownlint tool missing")
    add_hint "markdownlint unavailable: install markdownlint-cli2/markdownlint locally"
    return 127
}

run_markdownlint_local_check() {
    local args=()
    cd "$target_root"
    if [[ "$markdownlint_cmd" == "markdownlint-cli2" ]]; then
        if [[ "$config_mode" == "explicit" ]]; then
            args+=(--config "$markdownlint_config")
        fi
        markdownlint-cli2 "${args[@]}" -- "${markdown_files[@]}"
        return $?
    fi

    if [[ "$config_mode" == "explicit" ]]; then
        args=(-c "$markdownlint_config")
    fi
    markdownlint "${args[@]}" -- "${markdown_files[@]}"
    return $?
}

run_markdownlint_local_fix() {
    local args=()
    cd "$target_root"
    if [[ "$markdownlint_cmd" == "markdownlint-cli2" ]]; then
        if [[ "$config_mode" == "explicit" ]]; then
            args+=(--config "$markdownlint_config")
        fi
        markdownlint-cli2 "${args[@]}" --fix -- "${markdown_files[@]}"
        return $?
    fi

    if [[ "$config_mode" == "explicit" ]]; then
        args=(-c "$markdownlint_config")
    fi
    markdownlint "${args[@]}" -f -- "${markdown_files[@]}"
    return $?
}

json_out="false"
install_config="false"
target_root=""
schema_version="fixmd/v1"
tool_name="fixmd"
config_source="unknown"
config_kind="unknown"
config_mode="explicit"
config_supports_cli2="false"
config_supports_markdownlint="false"
markdownlint_config=""
markdownlint_cmd=""
template_path=""
temp_config_dir=""

trap cleanup EXIT

while [[ $# -gt 0 ]]; do
    case "$1" in
        --target)
            if [[ $# -lt 2 ]]; then
                echo "[ERROR] missing value for --target" >&2
                usage >&2
                exit "$EXIT_INVALID_INPUT"
            fi
            target_root="$2"
            shift 2
            ;;
        --json)
            json_out="true"
            shift
            ;;
        --install-config)
            install_config="true"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "[ERROR] unsupported argument: $1" >&2
            usage >&2
            exit "$EXIT_INVALID_INPUT"
            ;;
    esac
done

if [[ -z "$target_root" ]]; then
    echo "[ERROR] --target is required" >&2
    usage >&2
    exit "$EXIT_INVALID_INPUT"
fi
if [[ ! -d "$target_root" ]]; then
    echo "[ERROR] target directory not found: $target_root" >&2
    exit "$EXIT_INVALID_INPUT"
fi
target_root="$(cd "$target_root" && pwd)"

status="ok"
files_total=0
markdownlint_status="skipped"
toolchain_markdownlint="missing"
error_code=""
error_message=""
hints=()
failures=()
markdown_files=()
fix_applied="false"
needs_agent_refine="false"

if git -C "$target_root" rev-parse --show-toplevel >/dev/null 2>&1; then
    while IFS= read -r -d '' rel; do
        case "$rel" in
            .workflow/archive/*|node_modules/*|vendor/*)
                continue
                ;;
        esac
        markdown_files+=("$rel")
    done < <(git -C "$target_root" ls-files -z -- '*.md')
else
    while IFS= read -r -d '' abs; do
        rel="${abs#"$target_root"/}"
        markdown_files+=("$rel")
    done < <(find "$target_root" \
        -type f \
        -name '*.md' \
        -not -path '*/.git/*' \
        -not -path '*/node_modules/*' \
        -not -path '*/vendor/*' \
        -not -path '*/.workflow/archive/*' \
        -print0)
fi

files_total=${#markdown_files[@]}
if [[ "$files_total" -gt 0 || "$install_config" == "true" ]]; then
    resolve_markdownlint_config || exit "$EXIT_INVALID_INPUT"
    if [[ "$install_config" == "true" && "$config_source" == "existing" ]]; then
        add_hint "repo already defines markdownlint config; skipped --install-config"
    fi
fi

if [[ "$files_total" -eq 0 ]]; then
    emit_output
    exit "$EXIT_OK"
fi

snapshot_markdown_checksum() {
    local line
    (
        cd "$target_root"
        for line in "${markdown_files[@]}"; do
            [[ -f "$line" ]] || continue
            cksum -- "$line"
        done
    ) | cksum | awk '{print $1 ":" $2}'
}

lint_output=""
lint_rc=0
fix_output=""
fix_rc=0
before_fix_checksum=""
after_fix_checksum=""
has_cli2="false"
has_markdownlint="false"
if command -v markdownlint-cli2 >/dev/null 2>&1; then
    has_cli2="true"
fi
if command -v markdownlint >/dev/null 2>&1; then
    has_markdownlint="true"
fi

if choose_markdownlint_cmd; then
    before_fix_checksum="$(snapshot_markdown_checksum)"
    set +e
    fix_output="$(run_markdownlint_local_fix 2>&1)"
    fix_rc=$?
    lint_output="$(run_markdownlint_local_check 2>&1)"
    lint_rc=$?
    set -e

    if [[ "$markdownlint_cmd" == "markdownlint-cli2" && ( "$fix_rc" -eq 127 || "$lint_rc" -eq 127 ) && "$has_markdownlint" == "true" && "$config_supports_markdownlint" == "true" ]]; then
        markdownlint_cmd="markdownlint"
        add_hint "markdownlint-cli2 runtime unavailable; fell back to markdownlint"
        set +e
        fix_output="$(run_markdownlint_local_fix 2>&1)"
        fix_rc=$?
        lint_output="$(run_markdownlint_local_check 2>&1)"
        lint_rc=$?
        set -e
    elif [[ "$markdownlint_cmd" == "markdownlint-cli2" && ( "$fix_rc" -eq 127 || "$lint_rc" -eq 127 ) && "$config_supports_markdownlint" != "true" ]]; then
        add_hint "markdownlint-cli2 runtime unavailable and the detected repo config requires it"
    fi

    after_fix_checksum="$(snapshot_markdown_checksum)"
    if [[ "$before_fix_checksum" != "$after_fix_checksum" ]]; then
        fix_applied="true"
    fi
else
    lint_rc=127
    fix_rc=127
fi

if [[ "$lint_rc" -eq 0 ]]; then
    markdownlint_status="ok"
else
    markdownlint_status="error"
    status="error"
    if [[ "$lint_rc" -eq 127 ]]; then
        toolchain_markdownlint="missing"
        if [[ -z "$error_code" ]]; then
            error_code="tool_unavailable"
            error_message="required fixmd tools are unavailable"
        fi
    else
        append_markdownlint_failures "$lint_output"
        add_hint "fix markdown format issues under $target_root"
        needs_agent_refine="true"
        add_hint "auto-fix was insufficient: use agent refine on files in failures[]"
        if [[ -z "$error_code" ]]; then
            error_code="check_failed"
            error_message="fixmd validation failed"
        fi
    fi
fi

if [[ "$fix_rc" -ne 0 && "$fix_rc" -ne 127 ]]; then
    add_hint "markdownlint auto-fix returned non-zero; unresolved rules may require manual edits"
    if [[ "$markdownlint_status" == "error" ]]; then
        failures+=("markdownlint fix: $(first_line "$fix_output")")
    fi
fi

emit_output
exit_with_status
