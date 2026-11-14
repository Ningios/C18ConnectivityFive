#!/usr/bin/env python3
"""Remove the authorized settings screenshot carousel before signing/loading."""
import copy,hashlib,io,json,struct,tarfile
from pathlib import Path
from integrity import checked_slices,signature_check
from promo_cleanup import normalized_slice
PREFS='Library/PreferenceBundles/ControlCenter18Prefs.bundle/ControlCenter18Prefs'
ROOT='Library/PreferenceBundles/ControlCenter18Prefs.bundle/Screenshots'
ORIGINAL_SHA256='2b8685db2688dd3220d93f36b9d846c2c994f83ad7e41aff77e022aa14f9c79f'
# arm64/arm64e: skip UIScrollView creation, seven-image loop, then addSubview.
# NSMutableArray construction/publication stays: _shotViews.count == 0 makes
# the unmodified _layoutForWidth:apply: skip the entire 248pt screenshot row.
PATCHES={0:((0x4504,0x4560,'a80000b0'),(0x4594,0x468c,'98da43f9'),(0x46a0,0x46ac,'626a7cf8')),
         0x80000002:((0x451c,0x4578,'a80000b0'),(0x45ac,0x46a4,'98da43f9'),(0x46b8,0x46c4,'626a7cf8'))}
def sha(b):return hashlib.sha256(b).hexdigest()
def screenshot(name):return name==ROOT or name.startswith(ROOT+'/')
def branch(source,target):
 assert (target-source)%4==0 and -(1<<27)<=target-source<(1<<27)
 return struct.pack('<I',0x14000000|(((target-source)//4)&0x3ffffff))
def patched_prefs(original):
 assert sha(original)==ORIGINAL_SHA256,'Unreviewed settings binary'
 checked_slices(original);out=bytearray(original)
 for i in range(2):
  cpu,sub,base,size,align=struct.unpack_from('>5I',original,8+i*20)
  assert sub in PATCHES and cpu==0x100000c
  # All reviewed instruction addresses map directly inside __TEXT.__text.
  ncmd=struct.unpack_from('<I',original,base+16)[0];pos=base+32;regions=[]
  for _ in range(ncmd):
   cmd,n=struct.unpack_from('<II',original,pos)
   if cmd==0x19:
    for j in range(struct.unpack_from('<I',original,pos+64)[0]):
     sec=pos+72+80*j
     if original[sec:sec+16].rstrip(b'\0')==b'__text':
      va,length,off=struct.unpack_from('<QQI',original,sec+32);regions.append((va,length,off))
   pos+=n
  for va,target,preimage in PATCHES[sub]:
   area=[r for r in regions if r[0]<=va<target<r[0]+r[1]];assert len(area)==1
   start,length,off=area[0];p=base+off+va-start
   assert original[p:p+4]==bytes.fromhex(preimage),(hex(sub),hex(va))
   out[p:p+4]=branch(va,target)
 assert len(out)==len(original)
 return bytes(out)
def remove_resources(data):
 deleted={n:{'type':'file' if t.isfile() else 'directory','bytes':len(b or b''),'sha256':sha(b) if b else None} for n,(t,b) in data.items() if screenshot(n)}
 assert len(deleted)==15 and sum(e['type']=='file' for e in deleted.values())==14,'Unexpected screenshot input tree'
 assert sum(e['bytes'] for e in deleted.values())==1663235,'Unexpected screenshot content'
 for n in deleted:del data[n]
 return {'removed_entries':deleted,'removed_files':14,'removed_bytes':1663235,'carousel_creation_skipped':True,'image_loading_skipped':True,'empty_image_array_uses_existing_zero_count_layout':True,'removed_layout_height_pt':248,'runtime_verified':False}
def verify_signed_prefs(original,signed):
 expected=checked_slices(patched_prefs(original));actual=checked_slices(signed)
 for sub in expected:assert normalized_slice(expected[sub])==normalized_slice(actual[sub]),'Unreviewed settings code difference'
 return {hex(sub):signature_check(b) for sub,b in actual.items()}
if __name__=='__main__':
 import argparse
 ap=argparse.ArgumentParser();ap.add_argument('baseline');ap.add_argument('output');a=ap.parse_args()
 from package import deb_members,archive
 m=deb_members(Path(a.baseline).read_bytes());d=archive(next(v for k,v in m.items() if k.startswith('data.tar')))
 out=Path(a.output);out.parent.mkdir(parents=True,exist_ok=True);out.write_bytes(patched_prefs(d[PREFS][1]));print('SETTINGS_CAROUSEL_REMOVED_NEEDS_CODESIGN',sha(out.read_bytes()))
