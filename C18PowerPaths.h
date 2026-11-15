#ifndef C18_POWER_PATHS_H
#define C18_POWER_PATHS_H
#include <stddef.h>
#include <string.h>

// dladdr supplies this loaded image's physical installation path. RootHide
// changes the prefix; ordinary rootless uses /var/jb and rootful uses "".
static inline int C18PowerInstallRoot(const char *image,char *root,size_t capacity) {
    static const char suffix[]="/Library/MobileSubstrate/DynamicLibraries/C18ConnectivityFive.dylib";
    if (!image || image[0]!='/' || !root || !capacity) return 0;
    size_t length=strlen(image),tail=sizeof(suffix)-1;
    if (length<tail || strcmp(image+length-tail,suffix)) return 0;
    size_t count=length-tail;
    if (count>=capacity) return 0;
    memcpy(root,image,count);root[count]='\0';return 1;
}
static inline int C18PowerResolveHelper(const char *root,char *path,size_t capacity) {
    static const char logical[]="/usr/libexec/C18PowerHelper";
    if (!root || (root[0] && root[0]!='/') || !path || !capacity) return 0;
    size_t prefix=strlen(root),tail=sizeof(logical)-1;
    if (prefix && root[prefix-1]=='/') return 0;
    if (prefix>=capacity || tail>=capacity-prefix) return 0;
    memcpy(path,root,prefix);memcpy(path+prefix,logical,tail+1);return 1;
}
#endif
