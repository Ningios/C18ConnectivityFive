#!/usr/bin/env python3
"""Exercise production power paths/spawn with fakes; never execute iOS actions."""
from pathlib import Path
import hashlib,json,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[1]
text=(ROOT/'C18PowerMenu.m').read_text()
start=text.index('static int C18PowerSpawn(');body=text.index('{',start);depth=1;end=body+1
while depth:
    depth+=(text[end]=='{')-(text[end]=='}');end+=1
spawn=text[start:end]
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
static const char *image;
static int checks,spawns,dlok,realok,deny,spawnError,marks;
static char lastPath[PATH_MAX],lastArgs[4][PATH_MAX];
static int fakeDladdr(const void *p,Dl_info *out){(void)p;out->dli_fname=image;return dlok;}
static char *fakeRealpath(const char *p,char *out){if(!realok)return NULL;strcpy(out,p);return out;}
static int fakeAccess(const char *p,int mode){assert(mode==X_OK);checks++;strcpy(lastPath,p);if(deny){errno=EACCES;return -1;}return 0;}
static int fakeSpawn(pid_t *pid,const char *path,void *a,void *b,char *const argv[],char *const env[]){
    assert(!a&&!b&&!env);assert(!strcmp(path,lastPath));assert(!strcmp(argv[0],path));
    spawns++;strcpy(lastPath,path);int n=0;
    while(argv[n]){assert(n<3);strcpy(lastArgs[n],argv[n]);n++;}
    lastArgs[n][0]=0;*pid=123;return spawnError;
}
#define dladdr fakeDladdr
#define realpath fakeRealpath
#define access fakeAccess
#define posix_spawn fakeSpawn
'''+spawn+r'''
static void mark(void *context){(void)context;marks++;}
static void reset(const char *value){image=value;checks=spawns=marks=deny=spawnError=0;dlok=realok=1;memset(lastPath,0,sizeof(lastPath));memset(lastArgs,0,sizeof(lastArgs));}
int main(void){unsigned cases=0;char root[PATH_MAX],path[PATH_MAX],imagePath[PATH_MAX],wanted[PATH_MAX];
 const char *roots[]={"","/var/jb","/var/containers/Bundle/Application/.jbroot-1C818AF67FDA5115","/private/var/containers/Bundle/Application/.jbroot-ABCDEF"};
 const char *logical[]={"/usr/bin/launchctl","/usr/bin/killall","/usr/bin/sbreload","/usr/bin/ldrestart","/var/jb/bin/launchctl","/var/jb/usr/bin/killall","/var/jb/usr/bin/sbreload","/var/jb/usr/bin/ldrestart"};
 const char *tail[]={"/usr/bin/launchctl","/usr/bin/killall","/usr/bin/sbreload","/usr/bin/ldrestart","/bin/launchctl","/usr/bin/killall","/usr/bin/sbreload","/usr/bin/ldrestart"};
 const char *suffix="/Library/MobileSubstrate/DynamicLibraries/C18ConnectivityFive.dylib";
 const char *args[]={"reboot","userspace",NULL};
 for(unsigned r=0;r<4;r++){
  snprintf(imagePath,sizeof(imagePath),"%s%s",roots[r],suffix);
  assert(C18PowerInstallRoot(imagePath,root,sizeof(root)));assert(!strcmp(root,roots[r]));
  for(unsigned i=0;i<8;i++){
   snprintf(wanted,sizeof(wanted),"%s%s",roots[r],tail[i]);
   assert(C18PowerResolvePath(root,logical[i],path,sizeof(path)));assert(!strcmp(path,wanted));
   reset(imagePath);C18PowerRunContext result={0};assert(C18PowerSpawn(logical[i],args,&result));
   assert(!result.error&&checks==1&&spawns==1&&!strcmp(lastPath,wanted));
   assert(!strcmp(lastArgs[1],"reboot")&&!strcmp(lastArgs[2],"userspace")&&!lastArgs[3][0]);cases++;
  }
  for(int op=0;op<5;op++){
   reset(imagePath);C18PowerRunContext result={0};assert(C18PowerExecute((C18PowerOperation)op,C18PowerSpawn,mark,&result));
   assert(spawns==1&&checks==1&&marks==(op==4));assert(!strncmp(lastPath,roots[r],strlen(roots[r])));cases++;
  }
 }
 const char *badImages[]={"relative/Library/MobileSubstrate/DynamicLibraries/C18ConnectivityFive.dylib","/var/jb/Library/MobileSubstrate/DynamicLibraries/Other.dylib","/var/jb/Library/MobileSubstrate/DynamicLibraries/C18ConnectivityFive.dylib.extra","/too-short"};
 for(unsigned i=0;i<4;i++){reset(badImages[i]);C18PowerRunContext result={0};assert(!C18PowerSpawn(logical[0],args,&result));assert(!spawns&&!checks&&result.error==ENOENT);cases++;}
 assert(!C18PowerInstallRoot(NULL,root,sizeof(root)));assert(!C18PowerInstallRoot(suffix,root,0));
 assert(!C18PowerInstallRoot("/var/jb/Library/MobileSubstrate/DynamicLibraries/C18ConnectivityFive.dylib",root,7));
 const char *bad[]={"/var/jbSomething/usr/bin/killall","/usr/bin/../bin/killall","/bin/sh","/var/jb/usr/bin/sudo","killall"};
 for(unsigned i=0;i<5;i++){assert(!C18PowerResolvePath("/var/jb",bad[i],path,sizeof(path)));cases++;}
 assert(!C18PowerResolvePath("/var/jb/",logical[0],path,sizeof(path)));assert(!C18PowerResolvePath("relative",logical[0],path,sizeof(path)));
 assert(!C18PowerResolvePath("/var/jb",logical[0],path,strlen("/var/jb/usr/bin/launchctl")));
 reset(suffix);dlok=0;C18PowerRunContext result={0};assert(!C18PowerSpawn(logical[0],args,&result)&&!spawns&&!checks);cases++;
 reset(suffix);realok=0;assert(!C18PowerSpawn(logical[0],args,&result)&&!spawns&&!checks);cases++;
 reset(suffix);deny=1;assert(!C18PowerSpawn(logical[0],args,&result)&&!spawns&&result.error==EACCES);cases++;
 reset(suffix);spawnError=EPERM;assert(!C18PowerSpawn(logical[0],args,&result)&&spawns==1&&result.error==EPERM);cases++;
 reset(suffix);const char *tooMany[]={"a","b","c",NULL};assert(!C18PowerSpawn(logical[0],tooMany,&result)&&!spawns&&result.error==E2BIG);cases++;
 reset(suffix);assert(!C18PowerSpawn(NULL,args,&result)&&!spawns&&!checks);assert(!C18PowerSpawn(logical[0],NULL,&result)&&!spawns&&!checks);cases+=2;
 reset(suffix);deny=1;assert(!C18PowerExecute(C18PowerRespring,C18PowerSpawn,mark,&result));assert(checks==4&&!spawns);cases++;
 printf("PASS %u production resolver/spawn cases; only fake access/realpath/dladdr/posix_spawn used\n",cases);
}
'''
with tempfile.TemporaryDirectory(prefix='cc18-power-paths-') as td:
    td=Path(td);src=td/'test.c';binary=td/'test';src.write_text(code)
    p=subprocess.run(['cc','-std=gnu11','-O2','-Wall','-Wextra','-Werror','-I'+str(ROOT),str(src),'-o',str(binary)],capture_output=True,text=True,timeout=40)
    if p.returncode:raise AssertionError(p.stderr)
    p=subprocess.run([str(binary)],capture_output=True,text=True,timeout=15)
    if p.returncode:raise AssertionError((p.returncode,p.stdout,p.stderr))
print(json.dumps({'passed':True,'evidence':p.stdout.strip(),'real_power_commands_executed':False,'ios_runtime_verified':False,'sha256':{n:hashlib.sha256((ROOT/n).read_bytes()).hexdigest() for n in ('C18PowerMenu.m','C18PowerPaths.h','C18PowerBackend.h')}},indent=2))
