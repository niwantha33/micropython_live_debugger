#!/usr/bin/env bash
# Patch 0022 — Real-Time Analysis (RTA) Function Timing

set -euo pipefail
MPY_DIR="${MPY_DIR:-$HOME/micropython}"

python3 - <<'PY'
import os
mpy_dir = os.path.expanduser(os.environ.get("MPY_DIR", "~/micropython"))

# 1. Modify py/moddbg.h
p_h = mpy_dir + "/py/moddbg.h"
s_h = open(p_h).read()

old_decl = "extern volatile uint8_t mp_dbg_trace_enabled;"
new_decl = old_decl + "\nextern volatile uint8_t mp_dbg_rta_enabled;"

if old_decl not in s_h:
    raise SystemExit("FAIL: mp_dbg_trace_enabled decl not found in moddbg.h")
if "mp_dbg_rta_enabled" not in s_h:
    s_h = s_h.replace(old_decl, new_decl)

# Update the macro!
old_macro = "|| mp_dbg_stepping_out || mp_dbg_halt_pending)"
new_macro = "|| mp_dbg_stepping_out || mp_dbg_halt_pending || (mp_dbg_rta_enabled && !mp_dbg_muted))"

if old_macro not in s_h:
    raise SystemExit("FAIL: MP_DBG_HOOK macro not found in moddbg.h")
if "mp_dbg_rta_enabled && !mp_dbg_muted" not in s_h:
    s_h = s_h.replace(old_macro, new_macro)

open(p_h, "w").write(s_h)

# 2. Modify py/moddbg.c
p_c = mpy_dir + "/py/moddbg.c"
s_c = open(p_c).read()

# Add rta_enabled flag
old_flag = "volatile uint8_t mp_dbg_trace_enabled = 0;"
new_flag = old_flag + "\nvolatile uint8_t mp_dbg_rta_enabled = 0;"
if old_flag not in s_c:
    raise SystemExit("FAIL: trace_enabled flag not found in moddbg.c")
if "mp_dbg_rta_enabled =" not in s_c:
    s_c = s_c.replace(old_flag, new_flag)

# Inject python methods rta_on and rta_off
api_anchor = "static mp_obj_t m_trace_on(void)"
rta_api = """
static mp_obj_t m_rta_on(void) {
    mp_dbg_rta_enabled = 1;
    return mp_const_none;
}
static MP_DEFINE_CONST_FUN_OBJ_0(m_rta_on_obj, m_rta_on);

static mp_obj_t m_rta_off(void) {
    mp_dbg_rta_enabled = 0;
    return mp_const_none;
}
static MP_DEFINE_CONST_FUN_OBJ_0(m_rta_off_obj, m_rta_off);
"""
if "m_rta_on_obj" not in s_c:
    s_c = s_c.replace(api_anchor, rta_api + "\n" + api_anchor)

# Register methods in module
reg_anchor = "{ MP_ROM_QSTR(MP_QSTR_trace_on),"
rta_reg = """    { MP_ROM_QSTR(MP_QSTR_rta_on),      MP_ROM_PTR(&m_rta_on_obj) },
    { MP_ROM_QSTR(MP_QSTR_rta_off),     MP_ROM_PTR(&m_rta_off_obj) },
"""
if "MP_QSTR_rta_on" not in s_c:
    s_c = s_c.replace(reg_anchor, rta_reg + "    " + reg_anchor)

# Hook into shadow stack push/pop
shadow_update_search = """        if (found >= 0) {
            shadow_top = (uint8_t)(found + 1);
            shadow[found].fun_bc = (const void *)code_state->fun_bc;
        } else if (shadow_top < MP_DBG_SHADOW_MAX) {
            shadow[shadow_top].cs = cur_cs;
            shadow[shadow_top].fun_bc = (const void *)code_state->fun_bc;
            shadow_top++;
        }"""

shadow_update_replace = """        if (found >= 0) {
            if (mp_dbg_rta_enabled && found < shadow_top - 1) {
                uint32_t ts = mp_hal_ticks_us();
                dbg_push(0xAA);
                dbg_push(0x06); // RTA EXIT
                dbg_push(8);
                uint32_t f_ptr = (uint32_t)(uintptr_t)shadow[shadow_top - 1].fun_bc;
                dbg_push(f_ptr & 0xFF); dbg_push((f_ptr >> 8) & 0xFF); dbg_push((f_ptr >> 16) & 0xFF); dbg_push((f_ptr >> 24) & 0xFF);
                dbg_push(ts & 0xFF); dbg_push((ts >> 8) & 0xFF); dbg_push((ts >> 16) & 0xFF); dbg_push((ts >> 24) & 0xFF);
            }
            shadow_top = (uint8_t)(found + 1);
            shadow[found].fun_bc = (const void *)code_state->fun_bc;
        } else if (shadow_top < MP_DBG_SHADOW_MAX) {
            shadow[shadow_top].cs = cur_cs;
            shadow[shadow_top].fun_bc = (const void *)code_state->fun_bc;
            shadow_top++;
            if (mp_dbg_rta_enabled) {
                uint32_t ts = mp_hal_ticks_us();
                dbg_push(0xAA);
                dbg_push(0x05); // RTA ENTRY
                dbg_push(8);
                uint32_t f_ptr = (uint32_t)(uintptr_t)code_state->fun_bc;
                dbg_push(f_ptr & 0xFF); dbg_push((f_ptr >> 8) & 0xFF); dbg_push((f_ptr >> 16) & 0xFF); dbg_push((f_ptr >> 24) & 0xFF);
                dbg_push(ts & 0xFF); dbg_push((ts >> 8) & 0xFF); dbg_push((ts >> 16) & 0xFF); dbg_push((ts >> 24) & 0xFF);
            }
        }"""

if "RTA ENTRY" not in s_c:
    if shadow_update_search not in s_c:
        raise SystemExit("FAIL: shadow update snippet not found in moddbg.c")
    s_c = s_c.replace(shadow_update_search, shadow_update_replace)

# Mute 0x01 trace push when RTA is enabled
trace_push_search = "        if (in_scope) emit_trace(off16, *ip);"
trace_push_replace = "        if (in_scope && !mp_dbg_rta_enabled) emit_trace(off16, *ip);"

if "!mp_dbg_rta_enabled" not in s_c:
    if trace_push_search not in s_c:
        raise SystemExit("FAIL: trace push snippet not found in moddbg.c")
    s_c = s_c.replace(trace_push_search, trace_push_replace)

open(p_c, "w").write(s_c)

PY

grep -q 'mp_dbg_rta_enabled' "$MPY_DIR/py/moddbg.h" || { echo "FAIL: moddbg.h rta missing"; exit 1; }
grep -q 'RTA ENTRY' "$MPY_DIR/py/moddbg.c" || { echo "FAIL: moddbg.c RTA entry missing"; exit 1; }
echo "    0022 applied OK"
