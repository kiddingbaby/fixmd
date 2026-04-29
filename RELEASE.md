# Release Checklist

Use this checklist before publishing `fixmd`.

## Preflight

1. `make check`
2. `bash scripts/fixmd.sh --help`
3. `bash scripts/fixmd.sh --target "$(pwd)" --json`
4. `python3 tests/validate_contract.py`
5. Verify default zero-write behavior against a clean sample repo (no auto-created `.markdownlint.jsonc`).
6. `bash scripts/fixmd.sh --target "$(pwd)" --install-config`
7. `bash -n scripts/fixmd.sh`
8. Confirm `SKILL.md` frontmatter is valid and paths are correct.
9. Confirm `contracts/result.schema.json` matches current script output.

## Versioning

1. Update `CHANGELOG.md` (`[Unreleased]` -> new version section).
2. Choose semantic version:
   - `MAJOR`: breaking contract/behavior
   - `MINOR`: backward-compatible feature improvement
   - `PATCH`: bug fix/docs only

## Publish

1. Commit release changes.
2. Tag version:

```bash
git tag -a vX.Y.Z -m "fixmd vX.Y.Z"
git push origin vX.Y.Z
```

1. Create GitHub Release with:
   - Summary of changes
   - Breaking changes (if any)
   - Upgrade notes

## Post-release

1. Move remaining notes back to `[Unreleased]`.
2. Validate fresh install path in a clean environment.
