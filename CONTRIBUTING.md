# Contributing

## Scope

- Keep `fixmd` focused on Markdown lint/fix workflow.
- Do not add unrelated checks or heavy dependencies.

## Change Rules

1. Script-first: prefer changes in `scripts/fixmd.sh`.
2. Keep output contract stable (`contracts/result.schema.json`).
3. Update docs (`README.md`, `SKILL.md`, `CHANGELOG.md`) with every behavior change.
4. Preserve no-Docker, local-toolchain-first strategy.
5. Preserve zero-write default config strategy unless behavior is explicitly redesigned.

## Validation

Run at minimum:

```bash
make check
bash scripts/fixmd.sh --help
bash scripts/fixmd.sh --target "$(pwd)" --json
bash scripts/fixmd.sh --target "$(pwd)" --install-config
bash -n scripts/fixmd.sh
bash tests/smoke.sh
```

If behavior or contract changes:

- update `contracts/result.schema.json`
- update examples/sections in `README.md`
- add entry under `[Unreleased]` in `CHANGELOG.md`
