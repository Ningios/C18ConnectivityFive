#!/usr/bin/env python3
"""Remove local symbol/debug records only, on the real macOS build before signing."""
from pathlib import Path
import subprocess,struct,hashlib,json,sys

def slices(b):
 assert b[:4]==bytes.fromhex('cafebabe')
 result={}
 for i in range(struct.unpack_from('>I',b,4)[0]):
  cpu,sub,off,size,align=struct.unpack_from('>5I',b,8+20*i)
  assert cpu==0x100000c and sub in (0,0x80000002) and sub not in result
  assert off+size<=len(b);result[sub]=b[off:off+size]
 assert set(result)=={0,0x80000002};return result

def facts(b):
 p=32;sections={};links={};commands=[];sym=None;dysym=None
 for _ in range(struct.unpack_from('<I',b,16)[0]):
  cmd,z=struct.unpack_from('<II',b,p);assert z>=8 and p+z<=len(b)
  command=b[p:p+z]
  if cmd==0x19:
   seg=command[8:24].rstrip(b'\0');nsects=struct.unpack_from('<I',command,64)[0]
   for i in range(nsects):
    q=p+72+i*80;sect=b[q:q+16].rstrip(b'\0');size=struct.unpack_from('<Q',b,q+40)[0];off=struct.unpack_from('<I',b,q+48)[0];flags=struct.unpack_from('<I',b,q+64)[0]&255
    if flags in (1,12,18):content=None
    else:assert off+size<=len(b);content=hashlib.sha256(b[off:off+size]).hexdigest()
    sections[(seg.decode(),sect.decode())]=(command[8:32].hex(),b[q+32:q+80].hex(),content)
  elif cmd==2:sym=struct.unpack_from('<4I',b,p+8)
  elif cmd==0xb:dysym=struct.unpack_from('<18I',b,p+8)
  elif cmd==0x1d:pass
  elif cmd in (0x22,0x80000022):
   sizes=struct.unpack_from('<10I',b,p+8)
   links[hex(cmd)]=[b[off:off+size].hex() for off,size in zip(sizes[::2],sizes[1::2])]
  elif cmd in (0x80000033,0x80000034,0x26,0x29):
   off,size=struct.unpack_from('<II',b,p+8);assert off+size<=len(b);links[hex(cmd)]=b[off:off+size].hex()
  else:commands.append(command.hex())
  p+=z
 assert sym;so,count,st,size=sym;globals=[]
 for i in range(count):
  nstr,typ,sect,desc,value=struct.unpack_from('<IBBHQ',b,so+i*16)
  if not (typ&1):continue
  assert nstr<size;end=b.index(b'\0',st+nstr,st+size);name=b[st+nstr:end].decode('utf-8')
  globals.append((name,typ,sect,desc,value))
 indirect=[]
 if dysym:
  for i in range(dysym[13]):
   value=struct.unpack_from('<I',b,dysym[12]+4*i)[0]
   if value&0xc0000000:indirect.append(('special',value));continue
   assert value<count;nstr=struct.unpack_from('<I',b,so+value*16)[0]
   end=b.index(b'\0',st+nstr,st+size);indirect.append(('symbol',b[st+nstr:end].decode('utf-8')))
  assert dysym[15]==dysym[17]==0,'Legacy relocation tables need separate verification'
 return {'sections':sections,'links':links,'commands':commands,'globals':sorted(globals),'indirect_symbols':indirect}

def verify(before,after):
 a=slices(before);b=slices(after)
 for sub in a:assert facts(a[sub])==facts(b[sub]),('Runtime/export/import changed',hex(sub))
 assert len(after)<len(before),'Local-symbol stripping did not shrink'
 return {'runtime_sections_exports_imports_fixups_unchanged':True,'slices':['0x0','0x80000002'],'before_bytes':len(before),'after_unsigned_bytes':len(after),'saved_unsigned_bytes':len(before)-len(after),'requires_resign':True}

def main():
 result={}
 for arg in sys.argv[1:]:
  p=Path(arg);before=p.read_bytes();subprocess.run(['xcrun','strip','-x',str(p)],check=True)
  result[str(p)]=verify(before,p.read_bytes())
 Path('build/local-symbol-strip-validation.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result),flush=True)
if __name__=='__main__':main()
