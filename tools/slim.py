"""Pinned static-only lossless optimization; never alter runtime paths or links."""
import copy,hashlib,json,tarfile,posixpath,base64,struct,zlib

PNG_PREFIXES=tuple('Library/Application Support/ControlCenter18/'+p+'/' for p in ('Controls18','DeviceGlyphs','Symbols','Packages'))
PNG_INPUT_FINGERPRINT='5b834c7c2ba77a8e74b8ac792a6fa6a8c95e11b8aead7d4a7aead9e042fceec4'
def png_inputs(data):
 return {n:hashlib.sha256(b).hexdigest() for n,(t,b) in data.items() if n.startswith(PNG_PREFIXES) and n.endswith('.png') and t.isfile()}

def png_chunks(b):
 assert b[:8]==b'\x89PNG\r\n\x1a\n','PNG signature'
 p=8;out=[]
 while p<len(b):
  assert p+12<=len(b),'PNG chunk header'
  size=struct.unpack_from('>I',b,p)[0];kind=b[p+4:p+8];end=p+12+size
  assert end<=len(b),'PNG chunk bounds'
  value=b[p+8:p+8+size]
  assert zlib.crc32(kind+value)&0xffffffff==struct.unpack_from('>I',b,p+8+size)[0],'PNG CRC'
  out.append((kind,value,b[p:end]));p=end
 assert out[0][0]==b'IHDR' and len(out[0][1])==13 and out[-1][:2]==(b'IEND',b'')
 return out

def png_content(b):
 c=png_chunks(b)
 # CgBI uses raw deflate/premultiplication; APNG has multiple frame streams.
 assert not any(k in (b'CgBI',b'acTL',b'fcTL',b'fdAT') for k,_,_ in c),'special PNG not eligible'
 ids=[i for i,(k,_,_) in enumerate(c) if k==b'IDAT']
 assert ids and ids==list(range(ids[0],ids[-1]+1)),'nonconsecutive IDAT'
 d=zlib.decompressobj();raw=d.decompress(b''.join(v for k,v,_ in c if k==b'IDAT'))+d.flush()
 assert d.eof and not d.unused_data and not d.unconsumed_tail,'PNG zlib stream'
 return c,raw,ids

def png_samples(chunks,raw):
 # Undo PNG filters without changing a single sample, including RGB hidden
 # behind alpha=0 and packed-row padding. Interlaced/CgBI/APNG stay untouched.
 w,h,depth,color,comp,filt,interlace=struct.unpack('>IIBBBBB',chunks[0][1])
 assert w and h and comp==filt==interlace==0,'unsupported PNG layout'
 channels={0:1,2:3,3:1,4:2,6:4}[color]
 stride=(w*depth*channels+7)//8;bpp=max(1,(depth*channels+7)//8)
 assert len(raw)==h*(stride+1),'PNG scanline size'
 rows=[];prior=bytes(stride)
 for y in range(h):
  p=y*(stride+1);kind=raw[p];row=bytearray(raw[p+1:p+1+stride])
  if kind==0:pass
  elif kind==1:
   for i in range(bpp,stride):row[i]=(row[i]+row[i-bpp])&255
  elif kind==2:row=bytearray((a+b)&255 for a,b in zip(row,prior))
  elif kind in (3,4):
   for i in range(stride):
    a=row[i-bpp] if i>=bpp else 0;b=prior[i];c=prior[i-bpp] if i>=bpp else 0
    if kind==3:predict=(a+b)//2
    else:
     p0=a+b-c;pa=abs(p0-a);pb=abs(p0-b);pc=abs(p0-c)
     predict=a if pa<=pb and pa<=pc else b if pb<=pc else c
    row[i]=(row[i]+predict)&255
  else:raise AssertionError('invalid PNG filter')
  rows.append(bytes(row));prior=row
 return rows

def verify_png_equivalent(before,after):
 a,ar,ai=png_content(before);b,br,bi=png_content(after)
 # Preserve IHDR, palette/alpha, ICC/gamma/sRGB, pHYs/scale and ALL
 # ancillary bytes/order. Only the reversible row filter may differ.
 assert [(k,v) for k,v,_ in a if k!=b'IDAT']==[(k,v) for k,v,_ in b if k!=b'IDAT'],'PNG metadata changed'
 assert ai[0]==bi[0],'PNG IDAT position changed'
 assert ar==br or png_samples(a,ar)==png_samples(b,br),'PNG samples changed'
 assert len(after)<len(before),'PNG optimization must shrink'
 return True

def recompress_png(before):
 c,raw,ids=png_content(before);best=before
 candidates=[(raw,(zlib.Z_DEFAULT_STRATEGY,zlib.Z_FILTERED))]
 # One bounded alternative, not an exhaustive optimizer. No color/depth,
 # palette, metadata or invisible-pixel reductions; stdlib-only on macOS/Linux.
 if c[0][1][-1]==0 and len(raw)<=512*1024:
  unfiltered=b''.join(b'\0'+row for row in png_samples(c,raw))
  if unfiltered!=raw:candidates.append((unfiltered,(zlib.Z_DEFAULT_STRATEGY,zlib.Z_FILTERED,zlib.Z_RLE)))
 for scanlines,strategies in candidates:
  for strategy in strategies:
   co=zlib.compressobj(9,zlib.DEFLATED,15,9,strategy);payload=co.compress(scanlines)+co.flush()
   block=struct.pack('>I',len(payload))+b'IDAT'+payload+struct.pack('>I',zlib.crc32(b'IDAT'+payload)&0xffffffff)
   after=before[:8]+b''.join(block if i==ids[0] else v for i,(k,_,v) in enumerate(c) if k!=b'IDAT' or i==ids[0])
   if len(after)<len(best):best=after
 if best!=before:verify_png_equivalent(before,best)
 return best

from pathlib import Path
LOCALIZATION=json.loads((Path(__file__).resolve().parents[1]/'Resources/Localization/manifest.json').read_text())
# Exact static-only editor leftovers, reviewed independently of compression.
UNUSED_ASSETS=json.loads(Path(__file__).with_name('unused-assets.json').read_text())
def remove_unused_assets(data,issued=False):
 for n,digest in UNUSED_ASSETS['descriptor_sha256'].items():
  assert n in data and hashlib.sha256(data[n][1]).hexdigest()==digest,'Animation descriptor changed: '+n
 removed={}
 for n,e in UNUSED_ASSETS['files'].items():
  t,b=data[n];digest=e['issued_sha256'] if issued else e['sha256'];size=e['issued_bytes'] if issued else e['bytes']
  assert t.isfile() and hashlib.sha256(b).hexdigest()==digest and len(b)==size,n
  needle=Path(n).name
  from urllib.parse import quote
  names={needle,quote(needle),quote(needle,safe='@')}
  assert not any(any(v.encode() in other or v.encode('utf-16-le') in other for v in names)
   for p,(i,other) in data.items() if other and p!=n),'Unused asset gained reference: '+n
  removed[n]=e;del data[n]
 return removed
# Authorized settings screenshot JPEGs are removed by settings_cleanup.
JPEG_RESOURCES=[]
def put_localization(data,overlay):
 added_dirs=set()
 for e in LOCALIZATION:
  n=e['target'];parts=n.split('/')[:-1]
  for j in range(1,len(parts)+1):
   parent='/'.join(parts[:j])
   if parent not in data:
    t=tarfile.TarInfo('./'+parent);t.type=tarfile.DIRTYPE;t.mode=0o755;t.uid=t.gid=0;t.uname=t.gname='root';data[parent]=(t,None);added_dirs.add(parent)
  if 'data' in e:
   b=base64.b64decode(e['data']);assert hashlib.sha256(b).hexdigest()==e['sha256'];overlay(data,n,b)
  else:
   t=copy.copy(data[n][0]) if n in data else tarfile.TarInfo('./'+n)
   t.type=tarfile.SYMTYPE;t.linkname=e['linkname'];t.mode=0o777;t.size=0;t.uid=t.gid=0;t.uname=t.gname='root';data[n]=(t,None)
 return added_dirs

def optimize(data):
 removed={}
 for n,(t,b) in list(data.items()):
  if not (n.endswith(('.ai','.eps')) and '/Packages/' in n):continue
  needle=Path(n).name.encode()
  assert not any(needle in value for name,(info,value) in data.items() if value and name!=n and not name.endswith(('.ai','.eps'))),'Referenced design source: '+n
  removed[n]=hashlib.sha256(b).hexdigest();del data[n]
 # Exact input set pinned to five4 (also unchanged in the issued beta6).
 # No bundle executable, signed file, Uptime, recording or localization paths.
 inputs=png_inputs(data)
 assert len(inputs)==347 and hashlib.sha256(json.dumps(inputs,sort_keys=True,separators=(',',':')).encode()).hexdigest()==PNG_INPUT_FINGERPRINT,'Unexpected static PNG input set'
 unused=remove_unused_assets(data)
 changed={};png_cache={}
 for n in inputs:
  if n in unused:continue
  t,b=data[n];digest=inputs[n]
  if digest not in png_cache:png_cache[digest]=recompress_png(b)
  after=png_cache[digest]
  if after==b:continue
  nt=copy.copy(t);nt.size=len(after);data[n]=(nt,after)
  changed[n]={'before_sha256':inputs[n],'after_sha256':hashlib.sha256(after).hexdigest(),'before_bytes':len(b),'after_bytes':len(after)}
 jpeg_changed={}
 for e in JPEG_RESOURCES:
  n=e['target'];t,b=data[n];assert t.isfile() and hashlib.sha256(b).hexdigest()==e['before_sha256'],n
  after=(Path(__file__).resolve().parents[1]/e['source']).read_bytes();assert hashlib.sha256(after).hexdigest()==e['after_sha256'] and len(after)==e['after_bytes']<len(b),n
  nt=copy.copy(t);nt.size=len(after);data[n]=(nt,after);jpeg_changed[n]=e
 # Never create hardlinks or symlinks: path/type/link metadata stays intact.
 return {'removed_unused_assets':unused,'removed_unused_bytes':sum(e['bytes'] for e in unused.values()),'removed_unreferenced_design_sources':removed,'deduplicated_resources':{},'deduplicated_uncompressed_bytes':0,'png_recompressed':changed,'png_uncompressed_saved_bytes':sum(e['before_bytes']-e['after_bytes'] for e in changed.values()),'png_input_fingerprint':PNG_INPUT_FINGERPRINT,'jpeg_optimized':jpeg_changed,'jpeg_uncompressed_saved_bytes':sum(e['before_bytes']-e['after_bytes'] for e in jpeg_changed.values())}

def resolved(data,name,seen=None):
 seen=set() if seen is None else seen;assert name not in seen,name;seen.add(name)
 t,b=data[name]
 if t.issym():return resolved(data,posixpath.normpath(posixpath.join(posixpath.dirname(name),t.linkname)),seen)
 if t.islnk():return resolved(data,t.linkname.removeprefix('./'),seen)
 assert t.isfile(),name;return b
