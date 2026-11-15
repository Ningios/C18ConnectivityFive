#!/usr/bin/env python3
"""Check the sha256 mapping in reviewed-source.json before compiling."""
import hashlib
import json
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parents[1]


def main():
    manifest = json.loads((ROOT / "reviewed-source.json").read_text(encoding="utf-8"))
    hashes = manifest.get("sha256")
    if not isinstance(hashes, dict) or not hashes:
        raise SystemExit("SOURCE_MISMATCH: expected a nonempty sha256 mapping")
    errors = []
    for name, digest in hashes.items():
        relative = PurePosixPath(name)
        path = ROOT / relative
        if (relative.is_absolute() or ".." in relative.parts
                or not path.resolve().is_relative_to(ROOT) or not path.is_file()):
            errors.append(name)
        elif hashlib.sha256(path.read_bytes()).hexdigest() != digest:
            errors.append(name)
    if errors:
        raise SystemExit("SOURCE_MISMATCH: " + ", ".join(errors))
    print("REVIEWED_SOURCE_OK", len(hashes), "files")


if __name__ == "__main__":
    main()
