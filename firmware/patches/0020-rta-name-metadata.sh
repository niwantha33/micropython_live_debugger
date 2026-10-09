#!/usr/bin/env bash
# Patch 0020 — optional RTA name metadata for live MicroPython bytecode functions.
#
# Adds a backward-compatible debug CDC frame:
#   0xAA, 0x07, length, fun_ptr:u32, bytecode_ptr:u32,
#   context_ptr:u32, UTF-8 simple function name (1..60 bytes).
# Existing 0x05/0x06 execution-segment timing frames are unchanged.
#
# The VM already holds a VALID mp_obj_fun_bc_t at this hook. Read the
# name through MicroPython's public internal helper, not guessed heap offsets.
# The bytecode/context values are identity tokens; the host must not
# dereference them as memory addresses.
#
# Bounded cache: no heap allocations in the VM hook, no name per opcode.
# A changed identity at the same fun pointer emits fresh metadata.
# If the ring cannot fit metadata AND timing frames, skip the optional name
# and retry on the next segment instead of sending half a metadata frame.

set -euo pipefail
python3 - <<'PY'
import os
from pathlib import Path

p = Path(os.path.expanduser(os.environ.get("MPY_DIR", "~/micropython"))) / "py/moddbg.c"
s = p.read_text()

marker = "static inline void emit_rta_name("
if marker in s:
    print("    0020 already applied")
    raise SystemExit(0)

def replace_once(before, after):
    global s
    if s.count(before) != 1:
        raise SystemExit("FAIL: RTA name metadata patch anchor absent/ambiguous: " + before[:75])
    s = s.replace(before, after, 1)

replace_once(
    '#include "py/objfun.h"',
    '#include "py/objfun.h"\n#include <string.h>',
)

state = r"""
// Live RTA names: bounded identity cache; never hold references to heap objects.
// Cached pointers are compared only, never dereferenced after an event.
#define RTA_NAME_SLOTS 64
typedef struct {
    const void *fun;
    const byte *bytecode;
    const mp_module_context_t *context;
    qstr name;
} rta_name_identity_t;
static rta_name_identity_t rta_name_seen[RTA_NAME_SLOTS];
static uint8_t rta_name_used = 0;
static uint8_t rta_name_next = 0;
"""
replace_once(
    "static const void *rta_last_fun_bc = NULL;",
    "static const void *rta_last_fun_bc = NULL;\n" + state,
)

helper = r"""
static inline size_t rta_ring_free(void) {
    uint16_t head = dbg_head;
    uint16_t tail = dbg_tail;
    return (head >= tail) ? (DBG_RING_SIZE - (head - tail) - 1) : (tail - head - 1);
}

static inline void rta_push_u32(uint32_t v) {
    dbg_push((uint8_t)(v & 0xFF));
    dbg_push((uint8_t)((v >> 8) & 0xFF));
    dbg_push((uint8_t)((v >> 16) & 0xFF));
    dbg_push((uint8_t)((v >> 24) & 0xFF));
}

static inline void emit_rta_name(const mp_obj_fun_bc_t *fun_bc) {
    // fun_bc is guaranteed live by mp_dbg_hook's current code_state.
    if (fun_bc == NULL) {
        return;
    }
    qstr name = mp_obj_fun_bc_get_name(fun_bc);
    const char *text = qstr_str(name);
    size_t len = strlen(text);
    if (len == 0 || len > 60) {
        return;
    }

    int existing = -1;
    for (int i = 0; i < rta_name_used; ++i) {
        if (rta_name_seen[i].fun == (const void *)fun_bc) {
            existing = i;
            if (rta_name_seen[i].bytecode == fun_bc->bytecode
                && rta_name_seen[i].context == fun_bc->context
                && rta_name_seen[i].name == name) {
                return;
            }
            break;
        }
    }

    const size_t payload = 12 + len;
    // Reserve room for this metadata and up to two subsequent 11-byte
    // RTA segment frames; naming must never crowd out timing data.
    if (rta_ring_free() < 3 + payload + 22) {
        return;
    }

    dbg_push(0xAA);
    dbg_push(0x07);
    dbg_push((uint8_t)payload);
    rta_push_u32((uint32_t)(uintptr_t)fun_bc);
    rta_push_u32((uint32_t)(uintptr_t)fun_bc->bytecode);
    rta_push_u32((uint32_t)(uintptr_t)fun_bc->context);
    for (size_t i = 0; i < len; ++i) {
        dbg_push((uint8_t)text[i]);
    }

    int slot;
    if (existing >= 0) {
        slot = existing;
    } else if (rta_name_used < RTA_NAME_SLOTS) {
        slot = rta_name_used++;
    } else {
        slot = rta_name_next;
        rta_name_next = (uint8_t)((rta_name_next + 1) % RTA_NAME_SLOTS);
    }
    rta_name_seen[slot].fun = (const void *)fun_bc;
    rta_name_seen[slot].bytecode = fun_bc->bytecode;
    rta_name_seen[slot].context = fun_bc->context;
    rta_name_seen[slot].name = name;
}

"""
replace_once(
    "static inline void emit_rta_segment(uint8_t type, const void *fun_bc, uint32_t ts_us) {",
    helper + "static inline void emit_rta_segment(uint8_t type, const void *fun_bc, uint32_t ts_us) {",
)
replace_once(
    "            emit_rta_segment(0x05, cur_fun_bc, now_us);",
    "            emit_rta_name(code_state->fun_bc);\n            emit_rta_segment(0x05, cur_fun_bc, now_us);",
)
replace_once(
    "static mp_obj_t m_rta_on(void) {\n    rta_last_code_state = NULL;",
    "static mp_obj_t m_rta_on(void) {\n    rta_name_used = 0;\n    rta_name_next = 0;\n    rta_last_code_state = NULL;",
)

p.write_text(s)
assert 'emit_rta_name(code_state->fun_bc);' in s
assert 'rta_push_u32((uint32_t)(uintptr_t)fun_bc->bytecode);' in s
print("    0020 RTA runtime name metadata applied")
PY
