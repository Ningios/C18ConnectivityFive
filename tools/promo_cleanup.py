#!/usr/bin/env python3
"""Pinned, offline promo removal. Never execute/sign/package a Mach-O here."""
import copy
import hashlib
import struct

MAIN = 'Library/MobileSubstrate/DynamicLibraries/ControlCenter18.dylib'
MODULES = 'Library/MobileSubstrate/DynamicLibraries/ControlCenter18Modules.dylib'
MAIN_SHA256 = 'bd6c8148b1547c2ffe902b07a2655221e10769185e60620a2b2134b818dcc339'
MODULES_SHA256 = '01ac116703abc37b9ad53b8a3574a56817edbee783f8a76e79c4323bf3e1a3e5'
ROOTS = (
    'Library/ControlCenter18/Bundles/PablofskyModule.bundle',
    'Library/ControlCenter18/Bundles/RyoModule.bundle',
    'Library/Application Support/ControlCenter18/Pablofsky',
    'Library/Application Support/ControlCenter18/Ryo',
)
IDS = ('com.evgeniy558.controlcenter18.pablofsky', 'com.evgeniy558.controlcenter18.ryo')
TOKENS = IDS + ('tg:@pablofskyyy', 'tg:@iOSDumps', 'Pablofsky', 'C18Ryo', 'Ryo/', 'RyoModule')
# Slice base / NSConstantArray object VA / count VA / absolute file offset.
# __DATA,__objc_arrayobj, count=2 -> 0; chained pointer slots are untouched.
PATCHES = (
    {'arch': 'arm64', 'subtype': 0, 'slice_offset': 0x4000,
     'array_va': 0xe31e0, 'count_va': 0xe31e8, 'file_offset': 0xe71e8,
     'items_va': 0xe1820, 'item_objects': (0xe31b0, 0xe31c8)},
    {'arch': 'arm64e', 'subtype': 0x80000002, 'slice_offset': 0x114000,
     'array_va': 0xeb1f0, 'count_va': 0xeb1f8, 'file_offset': 0x1ff1f8,
     'items_va': 0xe9830, 'item_objects': (0xeb1c0, 0xeb1d8)},
)
EXPECTED = bytes.fromhex('0200000000000000')
REPLACEMENT = bytes(8)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def removable(name):
    return any(name == root or name.startswith(root + '/') for root in ROOTS)


def snapshot(entry):
    info, data = entry
    return ({k: getattr(info, k) for k in ('name', 'type', 'mode', 'uid', 'gid',
             'uname', 'gname', 'mtime', 'linkname', 'devmajor', 'devminor', 'size')}, data)


def references(entries):
    """Complete remaining package token inventory, including binary offsets."""
    found = []
    for name, (_, data) in entries.items():
        if data is None:
            continue
        hits = {}
        for token in TOKENS:
            offsets = []
            start = 0
            while True:
                start = data.find(token.encode(), start)
                if start < 0:
                    break
                offsets.append(hex(start))
                start += len(token)
            if offsets:
                hits[token] = offsets
        if hits:
            found.append({'path': name, 'sha256': sha(data), 'references': hits})
    return found


def patched_main(data):
    assert sha(data) == MAIN_SHA256, 'Unreviewed ControlCenter18.dylib'
    assert struct.unpack_from('>II', data) == (0xcafebabe, 2)
    result = bytearray(data)
    for index, patch in enumerate(PATCHES):
        cpu, sub, off, size, align = struct.unpack_from('>IIIII', data, 8 + index * 20)
        assert (cpu, sub, off) == (0x100000c, patch['subtype'], patch['slice_offset'])
        assert struct.unpack_from('<III', data, off) == (0xfeedfacf, cpu, sub)
        pos = patch['file_offset']
        assert off <= pos and pos + 8 <= off + size
        assert data[pos:pos + 8] == EXPECTED, 'Catalog preimage mismatch'
        result[pos:pos + 8] = REPLACEMENT
    from pathlib import Path
    import json
    manifest=json.loads((Path(__file__).with_name('promo-patches.json')).read_text())
    assert manifest['original_sha256']==MAIN_SHA256
    # Clear only the proven, feature-exclusive function ranges. Retain tiny
    # zero-return stubs at each function entry so Mach-O metadata, init slots
    # and arm64e authenticated pointers remain structurally valid.
    stub=bytes.fromhex('000080d2c0035fd6') # mov x0,#0; ret, no PAC prologue/stack
    ret=bytes.fromhex('c0035fd6')
    for slice_info in manifest['slices']:
        for region in slice_info['ranges']:
            pos,n=region['file_offset'],region['size']
            assert sha(data[pos:pos+n])==region['original_sha256']
            result[pos:pos+n]=bytes(n)
            for a,b in zip(region['function_offsets'],region['function_ends']):
                code=stub if b-a>=8 else ret
                result[pos+a:pos+a+len(code)]=code
    for item in manifest['strings']:
        old,new=item['original'].encode(),item['replacement'].encode()
        assert len(old)==len(new)
        for offset in item['offsets']:
            assert result[offset:offset+len(old)]==old
            result[offset:offset+len(old)]=new
    assert len(result)==len(data)
    assert all(t.encode() not in result for t in TOKENS)
    return bytes(result)


def verify_cleanup(old, new):
    deleted = {name for name in old if removable(name)}
    assert len(deleted) == 31, 'Pinned baseline promotion tree changed'
    assert len([n for n in deleted if old[n][0].isfile()]) == 27
    assert set(old) - set(new) == deleted, 'Deletion outside reviewed promotion trees'
    assert not set(new) - set(old), 'Unexpected additions'
    assert not any(removable(n) for n in new)
    for name in set(old) - deleted - {MAIN}:
        assert snapshot(old[name]) == snapshot(new[name]), 'Unrelated entry changed: ' + name
    assert snapshot(old[MAIN])[0] == snapshot(new[MAIN])[0]
    assert new[MAIN][1] == patched_main(old[MAIN][1]), 'Unexpected main-library edit'
    assert sha(old[MODULES][1]) == MODULES_SHA256
    assert new[MODULES][1] == old[MODULES][1]
    return {'passed': True, 'unrelated_entries_identical': len(old) - len(deleted) - 1,
            'only_modified_file': MAIN, 'modified_byte_count': sum(a!=b for a,b in zip(old[MAIN][1],new[MAIN][1])),
            'catalog_item_counts': [0, 0], 'architecture_headers_identical': True}


def cleanup(entries):
    """Transform real tar entries in memory; the result needs macOS re-signing."""
    old = dict(entries)
    data = patched_main(old[MAIN][1])
    assert sha(old[MODULES][1]) == MODULES_SHA256
    removed = []
    for name in sorted(old):
        if removable(name):
            info, content = entries.pop(name)
            removed.append({'path': name, 'type': 'file' if info.isfile() else 'directory',
                            'bytes': len(content) if content is not None else 0,
                            'sha256': sha(content) if content is not None else None})
    info = copy.copy(old[MAIN][0])
    entries[MAIN] = (info, data)
    check = verify_cleanup(old, entries)
    report = {
        'status': 'catalog_resources_code_removed_needs_macos_signature',
        'baseline_data_entries': len(old), 'remaining_data_entries': len(entries),
        'removed_entries': len(removed), 'removed_files': 27, 'removed_directories': 4,
        'removed_bytes': sum(item['bytes'] for item in removed), 'removed': removed,
        'main_original_sha256': MAIN_SHA256, 'main_patched_sha256': sha(data),
        'catalog_patches': [dict(p, expected_hex=EXPECTED.hex(), replacement_hex=REPLACEMENT.hex()) for p in PATCHES],
        'verification': check, 'remaining_references': references(entries),
        'requires_macos_resign': True, 'packaging_blocked': True,
        'compiled_promo_bodies_erased': True, 'runtime_verified': False,
        'remaining_work': ['macOS codesign and real-device verification pending; inert Mach-O metadata and zero-return entry stubs intentionally retained.']
    }
    return report


def slices(data):
    assert struct.unpack_from('>II',data)==(0xcafebabe,2)
    out={}
    for i in range(2):
        cpu,sub,off,n,align=struct.unpack_from('>5I',data,8+i*20)
        assert cpu==0x100000c and sub in (0,0x80000002) and off+n<=len(data)
        out[sub]=data[off:off+n]
    assert set(out)=={0,0x80000002}
    return out


def normalized_slice(data):
    b=bytearray(data);assert struct.unpack_from('<I',b)[0]==0xfeedfacf
    pos=32;sigoff=None
    for i in range(struct.unpack_from('<I',b,16)[0]):
        cmd,n=struct.unpack_from('<II',b,pos);assert n>=8
        if cmd==0x19 and bytes(b[pos+8:pos+24]).rstrip(b'\0')==b'__LINKEDIT':
            b[pos+32:pos+40]=bytes(8);b[pos+48:pos+56]=bytes(8)
        if cmd==0x1d:
            sigoff,siglen=struct.unpack_from('<II',b,pos+8);b[pos+8:pos+16]=bytes(8)
        pos+=n
    assert sigoff is not None and sigoff<=len(b)
    return bytes(b[:sigoff])


def verify_codesign(data):
    import math
    reports=[]
    for sub,b in slices(data).items():
        pos=32;signature=None
        for i in range(struct.unpack_from('<I',b,16)[0]):
            cmd,n=struct.unpack_from('<II',b,pos)
            if cmd==0x1d:signature=struct.unpack_from('<II',b,pos+8)
            pos+=n
        assert signature
        start,size=signature;sig=b[start:start+size];assert struct.unpack_from('>I',sig)[0]==0xfade0cc0
        dirs=[]
        for j in range(struct.unpack_from('>I',sig,8)[0]):
            kind,off=struct.unpack_from('>II',sig,12+j*8)
            magic,length=struct.unpack_from('>II',sig,off)
            if magic!=0xfade0c02:continue
            cd=sig[off:off+length];ver,flags,ho,io,ns,nc,limit=struct.unpack_from('>7I',cd,8)
            hs,ht,platform,pb=struct.unpack_from('>4B',cd,36)
            if ver>=0x20300:limit=struct.unpack_from('>Q',cd,56)[0] or limit
            assert limit==start;page=1<<pb if pb else limit
            assert nc==(limit+page-1)//page
            alg={1:'sha1',2:'sha256',3:'sha256',4:'sha384'}[ht]
            for k in range(nc):
                assert hashlib.new(alg,b[k*page:min(limit,(k+1)*page)]).digest()[:hs]==cd[ho+k*hs:ho+(k+1)*hs],(sub,k)
            dirs.append({'algorithm':alg,'pages':nc})
        assert dirs;reports.append({'subtype':hex(sub),'code_directories':dirs})
    return reports


def verify_signed_main(original,signed):
    expected=slices(patched_main(original));actual=slices(signed)
    for sub in expected:assert normalized_slice(expected[sub])==normalized_slice(actual[sub]),('Unreviewed signed-main difference',hex(sub))
    assert all(token.encode() not in signed for token in TOKENS)
    return verify_codesign(signed)


if __name__=='__main__':
    import argparse,json
    from pathlib import Path
    ap=argparse.ArgumentParser();ap.add_argument('baseline');ap.add_argument('output');args=ap.parse_args()
    import tarfile,io
    b=Path(args.baseline).read_bytes();p=8;payload=None
    while p+60<=len(b):
        h=b[p:p+60];name=h[:16].decode().strip().rstrip('/');size=int(h[48:58]);data=b[p+60:p+60+size];p+=60+size+(size%2)
        if name.startswith('data.tar'):payload=data
    assert payload is not None
    with tarfile.open(fileobj=io.BytesIO(payload),mode='r:*') as t:
        name=next(x.name for x in t if x.name.removeprefix('./')==MAIN)
        data=t.extractfile(name).read()
    out=Path(args.output);out.parent.mkdir(parents=True,exist_ok=True);out.write_bytes(patched_main(data))
    print('PROMO_MAIN_PATCHED_NEEDS_CODESIGN',sha(out.read_bytes()))
