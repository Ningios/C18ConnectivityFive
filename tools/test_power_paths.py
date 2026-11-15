#!/usr/bin/env python3
"""Run production backend and path/spawn functions against fake OS calls only."""
from pathlib import Path
import hashlib,json,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[1]
text=(ROOT/'C18PowerMenu.m').read_text()
start=text.index('static int C18PowerSpawn(');body=text.index('{',start);depth=1;end=body+1
while depth:
    depth+=(text[end]=='{')-(text[end]=='}');end+=1
code=r'''
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <limits.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/types.h>
#include "C18PowerPaths.h"
#include "C18PowerBackend.h"
#define NSLog(...) ((void)0)
typedef struct {int error;} C18PowerRunContext;
typedef struct {const char *dli_fname;} Dl_info;
static char kC18PowerMenu;
static const char *image;
static int checks,spawns,dlok,realok,deny,spawnError;
static char lastPath[PATH_MAX],lastArgs[4][PATH_MAX];
static char *testEnvironment[]={"PATH=/fake",NULL};
#define environ testEnvironment
static int fakeDladdr(const void *p,Dl_info *out){assert(p==&kC18PowerMenu);out->dli_fname=image;return dlok;}
static char *fakeRealpath(const char *p,char *out){if(!realok)return NULL;strcpy(out,p);return out;}
static int fakeAccess(const char *p,int mode){assert(mode==X_OK);checks++;strcpy(lastPath,p);if(deny){errno=EACCES;return -1;}return 0;}
static int fakeSpawn(pid_t *pid,const char *path,void *a,void *b,char *const argv[],char *const env[]){
 assert(!a&&!b&&env==testEnvironment);assert(!strcmp(path,lastPath)&&!strcmp(argv[0],path));
 spawns++;int n=0;while(argv[n]){assert(n<3);strcpy(lastArgs[n],argv[n]);n++;}lastArgs[n][0]=0;*pid=123;return spawnError;
}
#define dladdr fakeDladdr
#define realpath fakeRealpath
#define access fakeAccess
#define posix_spawn fakeSpawn
'''+text[start:end]+r'''
static void reset(const char *value){image=value;checks=spawns=deny=spawnError=0;dlok=realok=1;memset(lastPath,0,sizeof(lastPath));memset(lastArgs,0,sizeof(lastArgs));}
static int calls,successAt;static const char *seenPath[5],*seenArg[5][3];
static int sequence(const char *p,const char *const *args,void *ctx){
 assert(ctx==(void*)123);seenPath[calls]=p;int i=0;while(args[i]){assert(i<2);seenArg[calls][i]=args[i];i++;}seenArg[calls][i]=NULL;calls++;return calls==successAt;
}
int main(void){unsigned cases=0;char root[PATH_MAX],path[PATH_MAX],imagePath[PATH_MAX],wanted[PATH_MAX];
 const char *roots[]={"","/var/jb","/var/containers/Bundle/Application/.jbroot-1C818AF67FDA5115","/private/var/containers/Bundle/Application/.jbroot-ABCDEF"};
 const char *logical[]={"/usr/bin/launchctl","/usr/bin/killall","/usr/bin/sbreload","/usr/bin/ldrestart","/var/jb/bin/launchctl","/var/jb/usr/bin/killall","/var/jb/usr/bin/sbreload","/var/jb/usr/bin/ldrestart"};
 const char *tail[]={"/usr/bin/launchctl","/usr/bin/killall","/usr/bin/sbreload","/usr/bin/ldrestart","/bin/launchctl","/usr/bin/killall","/usr/bin/sbreload","/usr/bin/ldrestart"};
 const char *suffix="/Library/MobileSubstrate/DynamicLibraries/C18ConnectivityFive.dylib";
 const char *args[]={"reboot","userspace",NULL};
 for(unsigned r=0;r<4;r++){
  snprintf(imagePath,sizeof(imagePath),"%s%s",roots[r],suffix);assert(C18PowerInstallRoot(imagePath,root,sizeof(root)));assert(!strcmp(root,roots[r]));
  for(unsigned i=0;i<8;i++){
   snprintf(wanted,sizeof(wanted),"%s%s",roots[r],tail[i]);assert(C18PowerResolvePath(root,logical[i],path,sizeof(path)));assert(!strcmp(path,wanted));
   reset(imagePath);C18PowerRunContext result={0};assert(C18PowerSpawn(logical[i],args,&result));
   assert(!result.error&&checks==1&&spawns==1&&!strcmp(lastPath,wanted));assert(!strcmp(lastArgs[1],"reboot")&&!strcmp(lastArgs[2],"userspace"));cases++;
  }
  for(int op=0;op<4;op++){reset(imagePath);C18PowerRunContext result={0};assert(C18PowerExecute((C18PowerOperation)op,C18PowerSpawn,&result));assert(spawns==1&&checks==1);cases++;}
 }
 const char *badImages[]={"relative/Library/MobileSubstrate/DynamicLibraries/C18ConnectivityFive.dylib","/var/jb/Library/MobileSubstrate/DynamicLibraries/Other.dylib","/var/jb/Library/MobileSubstrate/DynamicLibraries/C18ConnectivityFive.dylib.extra","/too-short"};
 for(unsigned i=0;i<4;i++){reset(badImages[i]);C18PowerRunContext result={0};assert(!C18PowerSpawn(logical[0],args,&result));assert(!spawns&&!checks&&result.error==ENOENT);cases++;}
 const char *bad[]={"/var/jbSomething/usr/bin/killall","/usr/bin/../bin/killall","/bin/sh","/var/jb/usr/bin/sudo","killall"};
 for(unsigned i=0;i<5;i++){assert(!C18PowerResolvePath("/var/jb",bad[i],path,sizeof(path)));cases++;}
 assert(!C18PowerInstallRoot(NULL,root,sizeof(root)));assert(!C18PowerInstallRoot(suffix,root,0));assert(!C18PowerResolvePath("/var/jb/",logical[0],path,sizeof(path)));
 assert(!C18PowerResolvePath("/var/jb",logical[0],path,strlen("/var/jb/usr/bin/launchctl")));
 C18PowerRunContext result={0};reset(suffix);dlok=0;assert(!C18PowerSpawn(logical[0],args,&result)&&!spawns&&!checks);cases++;
 reset(suffix);realok=0;assert(C18PowerSpawn(logical[0],args,&result)&&spawns==1);cases++;
 reset(suffix);deny=1;assert(!C18PowerSpawn(logical[0],args,&result)&&!spawns&&result.error==EACCES);cases++;
 reset(suffix);spawnError=EPERM;assert(!C18PowerSpawn(logical[0],args,&result)&&spawns==1&&result.error==EPERM);cases++;
 reset(suffix);const char *tooMany[]={"a","b","c",NULL};assert(!C18PowerSpawn(logical[0],tooMany,&result)&&!spawns&&result.error==E2BIG);cases++;
 reset(suffix);assert(!C18PowerSpawn(NULL,args,&result)&&!spawns&&!checks);assert(!C18PowerSpawn(logical[0],NULL,&result)&&!spawns&&!checks);cases+=2;
 const char *paths[4][4]={{"/usr/bin/launchctl","/usr/bin/launchctl","/var/jb/bin/launchctl"},{"/usr/bin/killall","/usr/bin/sbreload","/var/jb/usr/bin/killall","/var/jb/usr/bin/sbreload"},{"/usr/bin/ldrestart","/usr/bin/sbreload","/var/jb/usr/bin/ldrestart","/usr/bin/killall"},{"/usr/bin/launchctl","/var/jb/bin/launchctl","/usr/bin/ldrestart","/var/jb/usr/bin/ldrestart"}};
 const char *params[4][4][3]={{{"reboot","shutdown"},{"reboot"},{"reboot"}},{{"-SEGV","SpringBoard"},{NULL},{"-SEGV","SpringBoard"},{NULL}},{{NULL},{NULL},{NULL},{"-SEGV","SpringBoard"}},{{"reboot","userspace"},{"reboot","userspace"},{NULL},{NULL}}};
 for(int repeat=0;repeat<100;repeat++)for(int op=0;op<4;op++)for(int success=0;success<=(op==0?3:4);success++){
  calls=0;successAt=success;memset(seenArg,0,sizeof(seenArg));assert(C18PowerExecute((C18PowerOperation)op,sequence,(void*)123)==!!success);
  assert(calls==(success?success:(op==0?3:4)));for(int i=0;i<calls;i++){assert(!strcmp(paths[op][i],seenPath[i]));for(int j=0;j<3;j++){const char *a=params[op][i][j],*b=seenArg[i][j];assert((!a&&!b)||(a&&b&&!strcmp(a,b)));}}cases++;
 }
 calls=0;assert(!C18PowerExecute((C18PowerOperation)4,sequence,(void*)123));assert(!C18PowerExecute((C18PowerOperation)-1,sequence,(void*)123));assert(!C18PowerExecute(C18PowerShutdown,NULL,NULL));assert(!calls);
 printf("PASS %u production four-action paths, arguments and spawn cases; zero real power commands\n",cases);
}
'''
with tempfile.TemporaryDirectory(prefix='cc18-four-power-') as td:
    td=Path(td);src=td/'test.c';out=td/'test';src.write_text(code)
    p=subprocess.run(['cc','-std=gnu11','-O2','-Wall','-Wextra','-Werror','-I'+str(ROOT),str(src),'-o',str(out)],capture_output=True,text=True,timeout=40)
    assert p.returncode==0,p.stderr
    p=subprocess.run([str(out)],capture_output=True,text=True,timeout=15);assert p.returncode==0,(p.returncode,p.stdout,p.stderr)
print(json.dumps({'passed':True,'evidence':p.stdout.strip(),'real_power_commands_executed':False,'ios_runtime_verified':False,'sha256':{n:hashlib.sha256((ROOT/n).read_bytes()).hexdigest() for n in ('C18PowerMenu.m','C18PowerPaths.h','C18PowerBackend.h')}},indent=2))
