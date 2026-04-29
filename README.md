# fixmd

Script-first Markdown lint/fix tool built around `markdownlint-cli2` or `markdownlint`.

Default behavior:

- auto-fix first
- re-check immediately
- use a temporary built-in baseline when the target repo has no markdownlint config
- do not write config into the target repo unless explicitly asked

This repository is standalone. It can be used directly as a shell tool, or packaged as a skill by another system.

## Install

Clone the repository anywhere:

```bash
git clone <your-repo-url> fixmd
cd fixmd
```

No runtime bootstrap is required beyond local markdownlint tooling.

## Prerequisites

- install `markdownlint-cli2` or `markdownlint` locally
- if neither tool exists, the script returns `tool_unavailable`

Recommended install:

```bash
npm install -g markdownlint-cli2
markdownlint-cli2 --version
```

## Quick Start

```bash
bash scripts/fixmd.sh --target "$(pwd)" --json
```

Text output:

```bash
bash scripts/fixmd.sh --target "$(pwd)"
```

Persist the built-in baseline into the target repo:

```bash
bash scripts/fixmd.sh --target "$(pwd)" --install-config
```

## Config Strategy

1. reuse repo-root markdownlint config when present
2. if the target repo has no config, use a temporary fallback baseline via explicit `--config`
3. only write `.markdownlint.jsonc` into the target repo when `--install-config` is provided
4. support legacy `.markdownlintrc` as best effort; prefer migrating to `.markdownlint.jsonc`

Recognized repo-root config sources:

- `.markdownlint.{jsonc,json,yaml,yml,cjs,mjs}`
- `.markdownlint-cli2.{jsonc,yaml,cjs,mjs}`
- `package.json#markdownlint-cli2`
- `.markdownlintrc`（legacy）

## Runtime Strategy

1. detect repo config source and compatible toolchain
2. auto-fix markdownlint-fixable issues
3. re-run markdownlint immediately
4. if checks still fail, return `needs_agent_refine=true`

## Contract

- schema: `contracts/result.schema.json`
- `data.config.source|kind`
- `data.fix.applied|needs_agent_refine`
- `data.checks.markdownlint.status|toolchain`
- `data.failures[]` contains file-level failure summaries
- `error.code`：`invalid_input|tool_unavailable|check_failed|invalid_output`

## Exit Codes

- `0`: pass or no Markdown files found
- `1`: checks failed
- `2`: invalid input
- `4`: required lint tool missing

## Validation

Repository-level validation:

```bash
make check
```

Or run the commands directly:

```bash
bash -n scripts/fixmd.sh
bash tests/smoke.sh
```

## Release Checklist

Before release:

1. `bash scripts/fixmd.sh --help`
2. `bash scripts/fixmd.sh --target "<sample-repo>" --json` emits output matching `contracts/result.schema.json`
3. `bash tests/smoke.sh`
4. `assets/markdownlint.agent.jsonc` matches the documented rules
5. update `CHANGELOG.md` and cut a tag (`vX.Y.Z`)

## Troubleshooting

1. `error.code=tool_unavailable`

- confirm `markdownlint-cli2 --version` or `markdownlint --version` works
- if the target repo uses `.markdownlint-cli2.*` or `package.json#markdownlint-cli2`, install `markdownlint-cli2`
- if the target repo uses legacy `.markdownlintrc`, install `markdownlint` or migrate to `.markdownlint.jsonc`

1. `needs_agent_refine=true`

- auto-fix reached its limit; fix the files listed in `failures[]` and rerun

1. `config.source=temporary` appears in output

- the script used a temporary fallback baseline and did not write into the target repo

1. persist the baseline to a target repo

- rerun `bash scripts/fixmd.sh --target "$(pwd)" --install-config`.

## Built-in Rule Strategy

- full ruleset: `default: true`
- selected overrides: `MD013/024/025/029/033/040/041/046/048`
- when the target repo has no config, use a temporary `.markdownlint.jsonc` baseline and do not write into the repo
- only `--install-config` persists the baseline into the target repo
- template file: `assets/markdownlint.agent.jsonc`
