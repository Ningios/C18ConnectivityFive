#!/usr/bin/env python3
"""Prepare the reviewed Prefs transform and re-sign it on the Mac runner."""
import hashlib
import json
from pathlib import Path
import platform
import subprocess
from package import BASELINES, ROOT, archive, deb_members
from prefs_cleanup import patch, slices


def prepare():
    assert platform.system() == 'Darwin', 'Prefs must be signed by macOS codesign'
    build = ROOT / 'build'
    build.mkdir(exist_ok=True)
    reports = []
    for arch, prefix, digest in BASELINES:
        blob = (ROOT / f'Vendor/baseline-{arch}.deb').read_bytes()
        assert hashlib.sha256(blob).hexdigest() == digest
        members = deb_members(blob)
        data = archive(next(v for k, v in members.items() if k.startswith('data.tar')))
        name = prefix + 'Library/PreferenceBundles/ControlCenter18Prefs.bundle/ControlCenter18Prefs'
        original = data[name][1]
        transformed, changes = patch(original, arch)
        path = build / f'Prefs-{arch}.dylib'
        path.write_bytes(transformed)
        subprocess.run(['codesign', '--force', '--sign', '-', '--timestamp=none',
                        str(path)], check=True)
        subprocess.run(['codesign', '--verify', '--strict', '--all-architectures',
                        '--verbose=2', str(path)], check=True)
        signed = path.read_bytes()
        assert {sub for sub, _, _ in slices(signed)} == {0, 0x80000002}
        reports.append({'arch': arch, 'original_sha256': hashlib.sha256(original).hexdigest(),
                        'signed_sha256': hashlib.sha256(signed).hexdigest(),
                        'changes': changes, 'macos_codesign_strict_all_architectures': True})
    (build / 'prefs-cleanup.json').write_text(json.dumps(reports, indent=2) + '\n')
    print('PREFS_THREE_ROWS_REMOVED_AND_SIGNED', flush=True)


if __name__ == '__main__':
    prepare()
