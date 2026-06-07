#!/usr/bin/env bash
# Patch 0020 — Asynchronous Halt
#
# Adds support for interrupting/pausing VM execution on the next opcode.

set -euo pipefail
MPY_DIR="${MPY_DIR:-$HOME/micropython}"

python3 - <<'PY'
import os
p_h = os.path.expanduser(os.environ.get("MPY_DIR", "~/micropython")) + "/py/moddbg.h"
s_h = open(p_h).read()

# Add declaration in moddbg.h
old_decl = "extern volatile uint8_t mp_dbg_paused;"
new_decl = old_decl + "\nextern volatile uint8_t mp_dbg_halt_pending;"
if old_decl not in s_h: raise SystemExit("FAIL: old_decl not found in moddbg.h")
s_h = s_h.replace(old_decl, new_decl)

# Update MP_DBG_HOOK macro check in moddbg.h
old_macro = "|| mp_dbg_stepping_out)"
new_macro = "|| mp_dbg_stepping_out || mp_dbg_halt_pending)"
if old_macro not in s_h: raise SystemExit("FAIL: old_macro not found in moddbg.h")
s_h = s_h.replace(old_macro, new_macro)

open(p_h, "w").write(s_h)

p_c = os.path.expanduser(os.environ.get("MPY_DIR", "~/micropython")) + "/py/moddbg.c"
s_c = open(p_c).read()

# Add definition in moddbg.c
old_def = "volatile uint8_t mp_dbg_paused = 0;"
new_def = old_def + "\nvolatile uint8_t mp_dbg_halt_pending = 0;"
if old_def not in s_c: raise SystemExit("FAIL: old_def not found in moddbg.c")
s_c = s_c.replace(old_def, new_def)

# Add halt check block in mp_dbg_hook (before breakpoints)
old_bp = "// --- breakpoints ---"
new_bp = """// --- halt ---
    if (mp_dbg_halt_pending) {
        mp_dbg_halt_pending = 0;
        paused_fun_bc = (const void *)code_state->fun_bc;
        paused_code_state = code_state;
        paused_ip_off = off16;
        emit_bp_hit(off16);
        mp_dbg_paused = 1;
        paused_shadow_top = shadow_top;
        for (int _i = 0; _i < shadow_top; _i++) paused_shadow[_i] = shadow[_i];
        while (mp_dbg_paused) {
            MP_DBG_BARRIER();
            mp_hal_delay_ms(1);
            mp_handle_pending(true);
        }
    }

    // --- breakpoints ---"""

if old_bp not in s_c: raise SystemExit("FAIL: old_bp hook anchor not found in moddbg.c")
s_c = s_c.replace(old_bp, new_bp, 1)

# Add m_halt definition in moddbg.c
old_globals = "static MP_DEFINE_CONST_FUN_OBJ_VAR_BETWEEN(m_globals_obj, 0, 1, m_globals);"
new_globals = old_globals + """

static mp_obj_t m_halt(void) {
    mp_dbg_halt_pending = 1;
    MP_DBG_BARRIER();
    return mp_const_none;
}
static MP_DEFINE_CONST_FUN_OBJ_0(m_halt_obj, m_halt);"""

if old_globals not in s_c: raise SystemExit("FAIL: m_globals definition not found in moddbg.c")
s_c = s_c.replace(old_globals, new_globals, 1)

# Register in globals table in moddbg.c
old_reg = "{ MP_ROM_QSTR(MP_QSTR_globals),      MP_ROM_PTR(&m_globals_obj) },"
new_reg = old_reg + "\n    { MP_ROM_QSTR(MP_QSTR_halt),         MP_ROM_PTR(&m_halt_obj) },"
if old_reg not in s_c: raise SystemExit("FAIL: globals registration not found in moddbg.c")
s_c = s_c.replace(old_reg, new_reg, 1)

open(p_c, "w").write(s_c)
PY

grep -q 'mp_dbg_halt_pending' "$MPY_DIR/py/moddbg.h" || { echo "FAIL: moddbg.h halt_pending missing"; exit 1; }
grep -q 'm_halt_obj' "$MPY_DIR/py/moddbg.c" || { echo "FAIL: m_halt missing"; exit 1; }
echo "    0020 applied OK"
