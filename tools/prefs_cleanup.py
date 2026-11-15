#!/usr/bin/env python3
"""Pinned removal of the two promotion groups, three rows and URL callback.

This edits the shipped Prefs executable; it is not recovered original source.
Mach-O pointer chains and unrelated identifiers/preferences remain unchanged.
The output must be re-signed before packaging.
"""
import hashlib
import struct

DIGESTS = {
    'arm64': '81c212c8a234e44a2f9fa8736f7d6ee5739d3bb5b5906d3f9963ac3f8b38bb8b',
    'arm64e': '098d23d3e75981f899bf99c6e0c607529195091d553c369387127f13d4c69ab2',
}
REMOVED_TEXT = (
    'REPOSITORY', 'LumiRepo', 'repo',
    'https://repo.ya-ebal.mom', 'c18URL', 'DEVELOPERS', 'evgeniy558',
    'https://t.me/e558558558', 'lumid_off', 'https://t.me/lumid_off', 'telegram',
)
PATCH = bytes.fromhex('ff0700f9f6031caa97000014')


def slices(data):
    assert struct.unpack_from('>II', data) == (0xcafebabe, 2)
    out = []
    for i in range(2):
        cpu, sub, off, size, align = struct.unpack_from('>5I', data, 8 + 20*i)
        assert cpu == 0x100000c and sub in (0, 0x80000002)
        assert off + size <= len(data) and off % (1 << align) == 0
        assert struct.unpack_from('<III', data, off) == (0xfeedfacf, cpu, sub)
        out.append((sub, off, size))
    assert len({s[0] for s in out}) == 2
    return out


def sections(b):
    out = {}; p = 32
    for _ in range(struct.unpack_from('<I', b, 16)[0]):
        cmd, n = struct.unpack_from('<II', b, p)
        assert n >= 8
        if cmd == 0x19:
            segment = b[p+8:p+24].rstrip(b'\0').decode()
            for i in range(struct.unpack_from('<I', b, p+64)[0]):
                q = p+72+i*80
                name = b[q:q+16].rstrip(b'\0').decode()
                addr, size, off = struct.unpack_from('<QQI', b, q+32)
                out[(segment, name)] = (addr, size, off)
        p += n
    return out


def patch(data, arch):
    assert hashlib.sha256(data).hexdigest() == DIGESTS[arch], 'Unreviewed Prefs baseline'
    result = bytearray(data); reports = []
    for sub, base, size in slices(data):
        old = data[base:base+size]; b = bytearray(old); sec = sections(old)
        start, end = (0x6540, 0x67a4) if sub == 0 else (0x6684, 0x68e8)
        handler = ((0x7698 if arch == 'arm64' else 0x7668) if sub == 0
                   else (0x7904 if arch == 'arm64' else 0x78d4))
        handler_end = handler + (0x90 if sub == 0 else 0xa4)
        expected = bytes.fromhex('779643f9600000d000e02591' if arch == 'arm64'
                                 else '779643f9600000d000002691')
        assert old[start:start+12] == expected
        assert old[end:end+12].hex() == 'f31f40f9486b73f8566b33f8'
        # Keep the existing array, initialize its removed temporary to nil,
        # then join the original ownership cleanup. Erase, do not hide, body.
        b[start:end] = PATCH + bytes(end-start-len(PATCH))
        b[handler:handler_end] = bytes(handler_end-handler)

        # Delete the relative ObjC method record, rebasing shifted records.
        a, n, off = sec[('__TEXT', '__objc_methlist')]
        lists = []
        for q in range(off, off+n-8, 4):
            flags, count = struct.unpack_from('<II', old, q)
            if flags != 0x8000000c or not 1 <= count <= 64 or q+8+count*12 > off+n:
                continue
            records = []
            for i in range(count):
                e = q+8+i*12
                values = struct.unpack_from('<3i', old, e)
                records.append(tuple(e+j*4+v for j, v in enumerate(values)))
            matches = [i for i, r in enumerate(records) if r[2] == handler]
            if matches:
                assert len(matches) == 1
                lists.append((q, flags, count, records, matches[0]))
        assert len(lists) == 1
        q, flags, count, records, idx = lists[0]
        assert count == 19 and idx == 10
        kept = records[:idx]+records[idx+1:]
        struct.pack_into('<I', b, q+4, count-1)
        for i, values in enumerate(kept):
            e = q+8+i*12
            struct.pack_into('<3i', b, e, *(v-(e+j*4) for j, v in enumerate(values)))
        b[q+8+(count-1)*12:q+8+count*12] = bytes(12)

        # Clear only exact standalone strings, not evgeniy558 in package IDs.
        a, n, off = sec[('__TEXT', '__cstring')]
        strings = {}; p = off
        while p < off+n:
            stop = old.find(b'\0', p, off+n)
            assert stop >= p
            text = old[p:stop]
            if text in {s.encode() for s in REMOVED_TEXT}:
                assert text not in strings
                strings[text] = (p, stop)
                b[p:stop] = bytes(stop-p)
            p = stop+1
        assert set(strings) == {s.encode() for s in REMOVED_TEXT}
        # CFString objects retain their valid chained pointer slots. Empty
        # values have length zero; no stale character count can over-read.
        a, n, off = sec[('__DATA_CONST', '__cfstring')]
        cleared_cf = []
        for p in range(off, off+n, 32):
            raw = struct.unpack_from('<Q', old, p+16)[0]
            target = raw & 0xffffffff
            if any(lo == target for lo, hi in strings.values()):
                struct.pack_into('<Q', b, p+24, 0)
                cleared_cf.append(p)
        assert len(cleared_cf) == len(REMOVED_TEXT)
        # Remove both developer name/URL pairs from the original constant array.
        a, n, off = sec[('__DATA_CONST', '__objc_arrayobj')]
        assert n == 72
        for p in range(off, off+n, 24):
            assert struct.unpack_from('<Q', old, p+8)[0] == 2
            struct.pack_into('<Q', b, p+8, 0)
        # Selector slot is unused after method/creation removal. Point its
        # existing chained target at a retained selector; preserve chain bits.
        name = old.find(b'openDeveloper:\0')
        keep = old.find(b'showLogs:\0')
        assert name >= 0 and keep >= 0 and old.count(b'openDeveloper:\0') == 1
        a, n, off = sec[('__DATA', '__objc_selrefs')]
        changed_slots = []
        for p in range(off, off+n, 8):
            raw = struct.unpack_from('<Q', old, p)[0]
            if raw & 0xffffffff == name:
                struct.pack_into('<Q', b, p, (raw & ~0xffffffff) | keep)
                changed_slots.append(p)
        assert len(changed_slots) == 1
        b[name:name+len(b'openDeveloper:')] = bytes(len(b'openDeveloper:'))
        assert b'openDeveloper:' not in b
        for text in ('LumiRepo', 'https://repo.ya-ebal.mom', 'lumid_off',
                     'https://t.me/e558558558', 'REPOSITORY', 'DEVELOPERS'):
            assert text.encode() not in b
        result[base:base+size] = b
        reports.append({'subtype': hex(sub), 'creation_range': [start, end],
                        'callback_erased': [handler, handler_end],
                        'method_count_before': count, 'method_count_after': count-1,
                        'cfstrings_emptied': len(cleared_cf),
                        'selector_slots_retargeted': changed_slots,
                        'developer_array_count': 0})
    assert len(result) == len(data)
    return bytes(result), reports
