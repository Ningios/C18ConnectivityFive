#!/usr/bin/env python3
"""Exercise only path construction with fake data; never runs a power action."""
from pathlib import Path
import hashlib, json, subprocess, tempfile
ROOT = Path(__file__).resolve().parents[1]
code = r'''
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "C18PowerPaths.h"
int main(void) {
    char root[512], path[512];
    const char *suffix = "/Library/MobileSubstrate/DynamicLibraries/C18ConnectivityFive.dylib";
    const char *roots[] = {"", "/var/jb", "/var/containers/Bundle/Application/.jbroot-ABC"};
    for (unsigned i = 0; i < sizeof(roots) / sizeof(*roots); ++i) {
        char image[512];
        snprintf(image, sizeof(image), "%s%s", roots[i], suffix);
        assert(C18PowerInstallRoot(image, root, sizeof(root)));
        assert(!strcmp(root, roots[i]));
        assert(C18PowerResolveHelper(root, path, sizeof(path)));
        char expected[512];
        snprintf(expected, sizeof(expected), "%s/usr/libexec/C18PowerHelper", roots[i]);
        assert(!strcmp(path, expected));
    }
    assert(!C18PowerInstallRoot("relative/Library/MobileSubstrate/DynamicLibraries/C18ConnectivityFive.dylib", root, sizeof(root)));
    assert(!C18PowerInstallRoot("/var/jb/Library/MobileSubstrate/DynamicLibraries/Other.dylib", root, sizeof(root)));
    assert(!C18PowerResolveHelper("/var/jb/", path, sizeof(path)));
    assert(!C18PowerResolveHelper("/var/jb", path, strlen("/var/jb/usr/libexec/C18PowerHelper")));
    puts("PASS power helper path cases; zero real power commands");
}
'''
with tempfile.TemporaryDirectory(prefix='cc18-power-paths-') as td:
    td = Path(td); src = td / 'test.c'; out = td / 'test'; src.write_text(code)
    p = subprocess.run(['cc', '-std=gnu11', '-O2', '-Wall', '-Wextra', '-Werror', '-I' + str(ROOT), str(src), '-o', str(out)], capture_output=True, text=True, timeout=30)
    assert p.returncode == 0, p.stderr
    p = subprocess.run([str(out)], capture_output=True, text=True, timeout=10)
    assert p.returncode == 0, (p.stdout, p.stderr)
print(json.dumps({'passed': True, 'evidence': p.stdout.strip(), 'real_power_commands_executed': False, 'ios_runtime_verified': False,
                  'sha256': {n: hashlib.sha256((ROOT / n).read_bytes()).hexdigest() for n in ('C18PowerMenu.m', 'C18PowerPaths.h', 'C18PowerBackend.h', 'C18PowerHelper.c')}}, indent=2))
