#!/usr/bin/env python3
"""Offline checks on both pinned baselines; does not sign or build a package."""
import hashlib
import struct
from pathlib import Path
from package import BASELINES, ROOT, archive, deb_members, slim_remove, remove_prefs_group_localizations
from prefs_cleanup import patch, sections, slices


def main():
    for arch, prefix, digest in BASELINES:
        blob = (ROOT / f'Vendor/baseline-{arch}.deb').read_bytes()
        assert hashlib.sha256(blob).hexdigest() == digest
        members = deb_members(blob)
        data = archive(next(v for k, v in members.items() if k.startswith('data.tar')))
        cleaned_strings = remove_prefs_group_localizations(data, prefix)
        assert len(cleaned_strings) == 4
        for n in cleaned_strings:
            assert b'REPOSITORY' not in data[n][1] and b'DEVELOPERS' not in data[n][1]
        prefs_path = prefix + 'Library/PreferenceBundles/ControlCenter18Prefs.bundle/'
        before = data[prefs_path + 'ControlCenter18Prefs'][1]
        after, changes = patch(before, arch)
        for filename in ('icon.png', 'icon@2x.png', 'icon@3x.png',
                         'header-icon.png', 'header-icon@2x.png', 'header-icon@3x.png'):
            name = prefs_path + filename
            assert name in data and data[name][1] and not slim_remove(name), name
        for filename in ('repo.png', 'telegram@3x.png', 'respring.png', 'Depiction/banner.png'):
            assert slim_remove(prefs_path + filename)
        for (sub, base, size), change in zip(slices(after), changes):
            b = after[base:base+size]
            lo, hi = change['creation_range']
            assert b[lo+12:hi] == bytes(hi-lo-12)
            hlo, hhi = change['callback_erased']
            assert b[hlo:hhi] == bytes(hhi-hlo)
            assert change['method_count_before'] == 19 and change['method_count_after'] == 18
            assert change['developer_array_count'] == 0
            sec = sections(b)
            a, n, off = sec[('__DATA_CONST', '__objc_arrayobj')]
            assert all(struct.unpack_from('<Q', b, off+i*24+8)[0] == 0 for i in range(3))
            for token in (b'LumiRepo', b'lumid_off', b'REPOSITORY', b'DEVELOPERS',
                          b'https://repo.ya-ebal.mom', b'https://t.me/e558558558',
                          b'openDeveloper:'):
                assert token not in b, token
        print('PREFS_SOURCE_TEST_OK', arch, 'both slices, two icon families')


if __name__ == '__main__':
    main()
