#!/usr/bin/env python3
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

import jsonschema


def main() -> int:
    repo_root = Path(__file__).resolve().parent.parent
    entry = repo_root / "scripts" / "fixmd.sh"
    contract = repo_root / "contracts" / "result.schema.json"
    envelope = repo_root / "contracts" / "skill-result.schema.json"

    with tempfile.TemporaryDirectory() as tmpdir:
        target = Path(tmpdir) / "repo"
        docs = target / "docs"
        docs.mkdir(parents=True)
        (docs / "ok.md").write_text("# Sample\n\nSome markdown content.\n", encoding="utf-8")

        result = subprocess.run(
            ["bash", str(entry), "--target", str(target), "--json"],
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode not in (0, 1):
            print(result.stdout)
            print(result.stderr, file=sys.stderr)
            raise SystemExit(f"unexpected exit code: {result.returncode}")

        payload = json.loads(result.stdout)
        schema = json.loads(contract.read_text(encoding="utf-8"))
        envelope_schema = json.loads(envelope.read_text(encoding="utf-8"))
        store = {
            schema["$id"]: schema,
            envelope_schema["$id"]: envelope_schema,
            contract.resolve().as_uri(): schema,
            envelope.resolve().as_uri(): envelope_schema,
            "https://raw.githubusercontent.com/kiddingbaby/fixmd/main/contracts/result.schema.json": schema,
            "https://raw.githubusercontent.com/kiddingbaby/fixmd/main/contracts/result.schema.legacy.json": schema,
            "https://raw.githubusercontent.com/kiddingbaby/fixmd/main/contracts/skill-result.schema.json": envelope_schema,
        }
        resolver = jsonschema.RefResolver(
            base_uri=contract.resolve().as_uri(),
            referrer=schema,
            store=store,
        )
        validator = jsonschema.Draft202012Validator(schema, resolver=resolver)
        errors = sorted(validator.iter_errors(payload), key=lambda e: list(e.path))
        if errors:
            raise SystemExit(errors[0].message)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
