"""Strict static validation of the pinned ad-hoc Mach-O format."""
import hashlib,struct

def require(value,why):
    if not value:raise AssertionError(why)
def within(off,size,limit,why):require(off>=0 and size>=0 and off+size<=limit,why)
def checked_slices(data):
    require(struct.unpack_from('>II',data)==(0xcafebabe,2),'exactly two fat slices')
    result={};ranges=[]
    for i in range(2):
        cpu,sub,off,size,align=struct.unpack_from('>5I',data,8+i*20)
        require(cpu==0x100000c and sub in (0,0x80000002) and sub not in result,'unique arm64/arm64e')
        require(align<=30 and off>=48 and off%(1<<align)==0,'fat slice alignment')
        within(off,size,len(data),'slice bounds');require(size>=32,'slice header')
        for a,z in ranges:require(off>=z or off+size<=a,'nonoverlapping slices')
        ranges.append((off,off+size));b=data[off:off+size]
        magic,icpu,isub,typ,ncmds,cmdsz,flags,res=struct.unpack_from('<8I',b)
        require((magic,icpu,isub,typ)==(0xfeedfacf,cpu,sub,6),'inner header agrees')
        within(32,cmdsz,len(b),'load command table');require(ncmds<=cmdsz//8,'command count')
        result[sub]=b
    require(set(result)=={0,0x80000002},'exact architecture set');return result

def signature_check(b):
    pos=32;end=32+struct.unpack_from('<I',b,20)[0];signature=None;link=None;link_ranges=[]
    for _ in range(struct.unpack_from('<I',b,16)[0]):
        within(pos,8,end,'command header');cmd,n=struct.unpack_from('<II',b,pos)
        require(n>=8 and n%8==0,'command size/alignment');within(pos,n,end,'command size')
        if cmd==0x19:
            require(n>=72,'segment command');name=b[pos+8:pos+24].rstrip(b'\0');vm,vs,fo,fs=struct.unpack_from('<4Q',b,pos+24)
            within(fo,fs,len(b),'segment file bounds')
            if name==b'__LINKEDIT':require(link is None,'one LINKEDIT');link=(vm,vs,fo,fs)
        if cmd==0x1d:
            require(signature is None and n==16,'one code signature');signature=struct.unpack_from('<II',b,pos+8)
        if cmd==2:
            require(n==24,'symtab size');so,nsy,st,sz=struct.unpack_from('<4I',b,pos+8);link_ranges.extend([(so,nsy*16),(st,sz)])
        if cmd==0xb:
            require(n==80,'dysymtab size');a=struct.unpack_from('<18I',b,pos+8)
            for oi,ni,unit in [(6,7,8),(8,9,56),(10,11,4),(12,13,4),(14,15,8),(16,17,8)]:
                if a[ni]:link_ranges.append((a[oi],a[ni]*unit))
        if cmd in (0x80000022,0x22):
            require(n==48,'dyld info size');a=struct.unpack_from('<10I',b,pos+8)
            link_ranges.extend((a[i],a[i+1]) for i in range(0,10,2) if a[i+1])
        if cmd in (0x1d,0x1e,0x26,0x29,0x2b,0x2e,0x80000033,0x80000034):
            require(n==16,'linkedit data command');off,size=struct.unpack_from('<II',b,pos+8)
            if size:link_ranges.append((off,size))
        pos+=n
    require(pos==end and signature is not None and link is not None,'complete load commands')
    vm,vs,fo,fs=link;start,size=signature
    require(vs>=fs and fs>0,'LINKEDIT virtual/file size')
    for off,n in link_ranges:require(fo<=off and off+n<=fo+fs,'LINKEDIT covers referenced data')
    require(start+size==len(b),'signature ends slice');within(start,size,len(b),'signature bounds')
    sig=b[start:start+size];magic,total,count=struct.unpack_from('>3I',sig)
    require(magic==0xfade0cc0 and 12<=total<=len(sig),'SuperBlob header')
    within(12,count*8,total,'SuperBlob index');blobs={};ranges=[]
    for i in range(count):
        kind,off=struct.unpack_from('>II',sig,12+i*8);within(off,8,total,'blob header')
        magic,n=struct.unpack_from('>II',sig,off)
        require(off>=12+count*8 and n>=8 and kind not in blobs,'blob index/size')
        within(off,n,total,'blob body')
        for a,z in ranges:require(off>=z or off+n<=a,'nonoverlapping blobs')
        ranges.append((off,off+n));blobs[kind]=(magic,sig[off:off+n])
    require(0 in blobs and blobs[0][0]==0xfade0c02,'primary CodeDirectory')
    require(65536 in blobs and blobs[65536]==(0xfade0b01,bytes.fromhex('fade0b0100000008')),'empty adhoc CMS wrapper')
    reports=[]
    for kind,(magic,cd) in blobs.items():
        if magic!=0xfade0c02:continue
        require(kind==0 or 0x1000<=kind<0x1006,'valid CodeDirectory slot')
        require(len(cd)>=88,'CodeDirectory header')
        ver,flags,ho,io,ns,nc,limit=struct.unpack_from('>7I',cd,8)
        require(ver==0x20400 and flags&2,'expected adhoc CodeDirectory version')
        hs,ht,platform,pb=struct.unpack_from('>4B',cd,36)
        require(ht in (1,2,3,4) and hs=={1:20,2:32,3:20,4:48}[ht],'hashSize matches hashType')
        require(pb<=24,'page size');limit=struct.unpack_from('>Q',cd,56)[0] or limit
        require(limit==start,'CodeDirectory covers all signed bytes')
        require(struct.unpack_from('>I',cd,44)[0]==0,'unsupported scatter rejected')
        require(88<=io<ho-ns*hs and b'\0' in cd[io:ho-ns*hs],'identifier bounds')
        require(ho-ns*hs>=88,'special hashes bounds');within(ho,nc*hs,len(cd),'code hashes bounds')
        page=1<<pb if pb else limit;require(nc==(limit+page-1)//page,'code page count')
        alg={1:'sha1',2:'sha256',3:'sha256',4:'sha384'}[ht]
        digest=lambda data:hashlib.new(alg,data).digest()[:hs]
        for k in range(nc):require(digest(b[k*page:min((k+1)*page,limit)])==cd[ho+k*hs:ho+(k+1)*hs],'code page hash')
        for k in range(1,ns+1):
            expected=digest(blobs[k][1]) if k in blobs else bytes(hs)
            require(cd[ho-k*hs:ho-(k-1)*hs]==expected,'special-slot hash')
        require(all(k>=0x1000 or k==0 or k<=ns for k in blobs),'all embedded special slots covered')
        reports.append({'slot':kind,'hash_type':ht,'hash_size':hs,'code_pages':nc,'special_slots':ns,'code_and_special_hashes_valid':True})
    require(bool(reports),'CodeDirectories present')
    return {'linkedit':{'file_offset':fo,'file_size':fs,'vm_size':vs,'referenced_ranges_valid':True},'code_directories':reports,'adhoc_only':True}

def fields(raw):
    result={};key=None
    for line in raw.decode().splitlines():
        if line.startswith((' ','\t')):
            require(key is not None,'control continuation');result[key]+='\n'+line
        elif line:
            key,value=line.split(':',1);require(key not in result,'unique control fields');result[key]=value.lstrip()
    return result

def entry_meta(entry,size=True):
    info,data=entry
    names=['type','mode','uid','gid','uname','gname','mtime','linkname','devmajor','devminor']
    if size:names+=['size']
    return tuple(getattr(info,k) for k in names)
def record(e):return entry_meta(e)+(e[1],)

