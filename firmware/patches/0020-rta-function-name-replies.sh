#!/usr/bin/env bash
# Optional Pico RTA symbol prototype. This PATCHES MicroPython during a
# candidate firmware build; it must never modify deployed firmware.
#
# Why: RTA events contain the VM's mp_obj_fun_bc_t pointer, which usually
# points into the GC heap. Linker .map files cannot name heap allocations.
# Decode the current, VALID VM function object using MicroPython's own
# mp_obj_fun_bc_get_name(), then emit a normal 0x03 text reply:
#   rta_name=XXXXXXXX:function_name
# where XXXXXXXX is the 8-digit hex fun_bc pointer.
#
# This reuses the existing reply framing/protocol-5 transport. An older Studio
# simply logs the reply; a newer Studio can label the RTA row. No REPL access,
# heap walk, raw pointer API, on-device file edit or debugger protocol change.
set -euo pipefail

python3 - <<'PY'
import os
from pathlib import Path

p = Path(os.path.expanduser(os.environ.get("MPY_DIR", "~/micropython"))) / "py" / "moddbg.c"
s = p.read_text()

def require_one(old, new, label):
    global s
    if new in s:
        return
    if s.count(old) != 1:
        raise SystemExit("RTA name patch: expected one " + label)
    s = s.replace(old, new, 1)

require_one(
    '#include "py/moddbg.h"',
    '#include "py/moddbg.h"\n#include "py/objfun.h"\n#include "py/qstr.h"',
    "header anchor",
)

anchor = "static inline void emit_rta_segment(uint8_t type, const void *fun_bc, uint32_t ts_us) {"
helper = r'''
// RTA function names are requested from actual, live VM code_state->fun_bc
// objects. NEVER dereference user-supplied addresses or attempt to scan GC.
#define RTA_SYMBOL_CACHE_CAP 128
#define RTA_SYMBOL_MAX_NAME_BYTES 72

typedef struct _rta_symbol_seen_t {
    const void *fun_bc;
    const byte *bytecode;
} rta_symbol_seen_t;

static rta_symbol_seen_t rta_symbol_seen[RTA_SYMBOL_CACHE_CAP];
static void rta_symbol_reset(void) {
    for (unsigned int i = 0; i < RTA_SYMBOL_CACHE_CAP; i++) {
        rta_symbol_seen[i].fun_bc = NULL;
        rta_symbol_seen[i].bytecode = NULL;
    }
}

static inline bool rta_ring_can_write(size_t frame_len) {
    const uint16_t head = dbg_head;
    const uint16_t tail = dbg_tail;
    return ((tail + DBG_RING_SIZE - head - 1) % DBG_RING_SIZE) >= frame_len;
}

static void rta_emit_symbol_if_new(const void *ptr) {
    if (ptr == NULL) {
        return;
    }
    // ptr comes directly from an executing MicroPython bytecode code_state.
    const mp_obj_fun_bc_t *fun = (const mp_obj_fun_bc_t *)ptr;
    const byte *code = fun->bytecode;
    // Direct-mapped cache: one lookup per VM switch. Avoid the RTA timing
    // distortion caused by linearly scanning dozens of symbol slots.
    const unsigned int slot = ((uintptr_t)ptr >> 3) & (RTA_SYMBOL_CACHE_CAP - 1);
    if (rta_symbol_seen[slot].fun_bc == ptr && rta_symbol_seen[slot].bytecode == code) {
        return;
    }
    const char *name = qstr_str(mp_obj_fun_bc_get_name(fun));
    if (name == NULL || name[0] == '\0') {
        return;
    }

    size_t len = 0;
    while (len < RTA_SYMBOL_MAX_NAME_BYTES && name[len] != '\0') {
        len++;
    }
    // Format: "rta_name=" + 8 hex digits + ":" + bounded function name.
    static const char prefix[] = "rta_name=";
    const size_t payload_len = sizeof(prefix) - 1 + 8 + 1 + len;
    const size_t frame_len = payload_len + 3;
    // No partial reply frames when the trace ring is congested. A later
    // execution switch may retry the name because it is not cached below.
    if (!rta_ring_can_write(frame_len)) {
        return;
    }

    dbg_push(0xAA);
    dbg_push(0x03); // existing text reply: old hosts remain compatible
    dbg_push((uint8_t)payload_len);
    for (size_t i = 0; i < sizeof(prefix) - 1; i++) {
        dbg_push((uint8_t)prefix[i]);
    }
    uintptr_t address = (uintptr_t)ptr;
    static const char hex[] = "0123456789abcdef";
    for (int shift = 28; shift >= 0; shift -= 4) {
        dbg_push((uint8_t)hex[(address >> shift) & 0xf]);
    }
    dbg_push(':');
    for (size_t i = 0; i < len; i++) {
        dbg_push((uint8_t)name[i]);
    }
    // Safe re-emission on cache collision; never suppress a new VM object.
    rta_symbol_seen[slot].fun_bc = ptr;
    rta_symbol_seen[slot].bytecode = code;
}

'''
require_one(anchor, helper + anchor, "RTA segment helper")

# Original 0x05/0x06 RTA events also need whole-frame capacity checks:
# dbg_push() drops individual bytes on ring overflow, which could otherwise
# turn a truncated frame into an apparent but invalid function pointer.
require_one(
    "    uint32_t fun = (uint32_t)(uintptr_t)fun_bc;",
    "    if (!rta_ring_can_write(11)) { dbg_lost += 11; return; }\n"
    "    uint32_t fun = (uint32_t)(uintptr_t)fun_bc;",
    "complete 11-byte RTA event capacity",
)

old = '            emit_rta_segment(0x05, cur_fun_bc, now_us);'
new = '            rta_emit_symbol_if_new(cur_fun_bc);\n' + old
require_one(old, new, "RTA entry event")

old = '''static mp_obj_t m_rta_on(void) {
    rta_last_code_state = NULL;'''
new = '''static mp_obj_t m_rta_on(void) {
    rta_symbol_reset();
    rta_last_code_state = NULL;'''
require_one(old, new, "RTA session reset")

p.write_text(s)
for marker in ("rta_emit_symbol_if_new(cur_fun_bc);", "rta_symbol_reset();",
               "mp_obj_fun_bc_get_name(fun)", "rta_ring_can_write(frame_len)"):
    if marker not in s:
        raise SystemExit("RTA name patch incomplete: " + marker)
print("0020: bounded, live VM RTA function-name replies installed")
PY
