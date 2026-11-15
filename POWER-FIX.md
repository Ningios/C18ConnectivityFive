# CC18 beta6 four-action power menu

This revision physically removes the legacy power dylib, injection plist and RootHide patch symlink from both final packages. The pinned Vendor input packages remain reproducibility inputs only; their old power files are excluded by package.py and checked absent by verify_delivery.py.

C18PowerMenu.m contains only the context-menu UI and four operations: shutdown, respring, ldrestart and userspace restart. The old alert factory/presenter hooks, original-handler forwarding, safe-mode action, marker writer and backend enum entry are removed. There is no original-popup fallback.

Executable lookup derives the bootstrap prefix from a data address in the loaded companion rather than a signed arm64e function pointer. The executable check and spawn use the same resolved path. The four legacy command sequences and arguments are retained; children receive the process environment. A selection already accepted by UIKit is one-shot and is not rejected solely because its menu anchor was detached during dismissal.

Other module, configuration, icon, localization and uptime sources are unchanged. The existing core-signature renewal remains in place. Version stays 3.0-beta6.

Tests exercise the production command table and path/spawn functions with fake OS calls; no real power action is executed. CI checks source hashes, compiles both architectures and strictly verifies the final packages. Build and signature success do not prove the device's command permissions, exit status or reboot outcome. Installation and on-device actions are not automated.
