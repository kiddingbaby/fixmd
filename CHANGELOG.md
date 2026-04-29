# Changelog

All notable changes to `fixmd` are documented in this file.

## [Unreleased]

## [1.1.0] - 2026-03-08

### Changed

- Default config strategy is zero-write: when a repo has no markdownlint config, `fixmd` now uses a temporary fallback baseline
  instead of writing `.markdownlint.jsonc` into the target repo.
- Added explicit `--install-config` to persist the built-in baseline to repo root only when no repo config already exists.
- Expanded existing-config detection to cover `.markdownlint.*`, `.markdownlint-cli2.*`, `package.json#markdownlint-cli2`, and legacy `.markdownlintrc`.
- JSON/text reports now include detected config source and kind.
- Aligned manifest metadata wording around the zero-write default and bumped skill version to `1.1.0`.

### Fixed

- Avoided unintended target-repo mutations caused by implicit config bootstrap.
- Fail clearly when repo config requires `markdownlint-cli2` or `markdownlint` specifically.

## [1.0.0] - 2026-03-05

### Added

- Initial public release of `fixmd` skill and script workflow.
- Markdownlint-first auto-fix + re-check pipeline.
- JSON output contract: `fixmd/v1`.
- Built-in cross-repo baseline config bootstrap (`.markdownlint.jsonc`).

### Changed

- Local toolchain strategy: prefer `markdownlint-cli2`, fallback to `markdownlint`.
- Removed Docker fallback and non-markdownlint components to keep install/use path simple.

### Fixed

- Runtime fallback when `markdownlint-cli2` exists but is not runnable.
- Safer handling for markdown file paths with spaces/colon and `-`-prefixed filenames.
- Fail-fast behavior when bootstrap config copy fails.
