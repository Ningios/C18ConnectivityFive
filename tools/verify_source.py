#!/usr/bin/env python3
import hashlib,json
from pathlib import Path
root=Path(__file__).resolve().parents[1]
manifest=json.loads((root/'reviewed-source.json').read_text())
errors=[]
for name,digest in manifest['sha256'].items():
    p=root/name
    if not p.is_file() or hashlib.sha256(p.read_bytes()).hexdigest()!=digest:errors.append(name)
if errors:raise SystemExit('SOURCE_MISMATCH: '+', '.join(errors))
assert manifest['version']=='3.0-beta6'
assert hashlib.sha256((root/'Vendor/baseline.deb').read_bytes()).hexdigest()=='4c2f36e17adbfe6d78412e629d749ac331d5eaabd003b18286ee37a14a2979e2'
print('REVIEWED_SOURCE_OK',manifest['version'],len(manifest['sha256']),'files')
print('BASELINE_OK',manifest['base_commit'],manifest['base_sha256'])
