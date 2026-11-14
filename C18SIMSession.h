#pragma once
#include <stdint.h>
#include <stdbool.h>

// Main-thread state of ONE fresh expanded card. Its lifetime is never shared
// with the permanently attached compact controller.
typedef struct {
    uint64_t generation;
    bool active,reading,busy;
} C18SIMSession;
static inline C18SIMSession C18SIMSessionNew(void) {
    return (C18SIMSession){.generation=1,.active=true,.reading=false,.busy=false};
}
static inline uint64_t C18SIMSessionRead(C18SIMSession *s) {
    if (!s->active || s->busy || s->reading) return 0;
    s->reading=true; return ++s->generation;
}
static inline bool C18SIMSessionAcceptRead(C18SIMSession *s,uint64_t token) {
    if (!s->active || !s->reading || !token || token!=s->generation) return false;
    s->reading=false; return true;
}
static inline uint64_t C18SIMSessionAction(C18SIMSession *s) {
    if (!s->active || s->reading || s->busy) return 0;
    s->busy=true; return ++s->generation;
}
static inline bool C18SIMSessionAcceptAction(C18SIMSession *s,uint64_t token) {
    if (!s->active || !s->busy || !token || token!=s->generation) return false;
    s->busy=false; return true;
}
static inline void C18SIMSessionEnd(C18SIMSession *s) {
    s->active=false; s->reading=false; s->busy=false; ++s->generation;
}
