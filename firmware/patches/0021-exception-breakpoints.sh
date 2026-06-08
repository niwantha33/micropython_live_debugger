#!/usr/bin/env bash
# Patch 0021 — Exception Breakpoints (Uncaught Exceptions)
#
# Adds support for pausing VM execution when an uncaught exception occurs.

set -euo pipefail
MPY_DIR="${MPY_DIR:-$HOME/micropython}"

python3 - <<'PY'
import os
mpy_dir = os.path.expanduser(os.environ.get("MPY_DIR", "~/micropython"))

# 1. Modify py/moddbg.h
p_h = mpy_dir + "/py/moddbg.h"
s_h = open(p_h).read()

old_decl = "void mp_dbg_hook(const byte *ip, const mp_code_state_t *code_state);"
new_decl = "#include \"py/obj.h\"\nvoid mp_dbg_hook(const byte *ip, const mp_code_state_t *code_state);\nvoid mp_dbg_handle_exception(mp_obj_t exc, const mp_code_state_t *code_state);"

if old_decl not in s_h:
    raise SystemExit("FAIL: old_decl not found in moddbg.h")
s_h = s_h.replace(old_decl, new_decl)
open(p_h, "w").write(s_h)

# 2. Modify py/moddbg.c
p_c = mpy_dir + "/py/moddbg.c"
s_c = open(p_c).read()

# Add mp_dbg_handle_exception implementation before the Python API (e.g. before m_trace_on)
old_anchor = "static mp_obj_t m_trace_on(void)"
impl = """void mp_dbg_handle_exception(mp_obj_t exc, const mp_code_state_t *code_state) {
    if (pump_fun_bc == NULL || (const void *)code_state->fun_bc == pump_fun_bc || mp_dbg_muted) {
        return;
    }

    // Filter out StopIteration and GeneratorExit
    if (mp_obj_is_subclass_fast(MP_OBJ_FROM_PTR(mp_obj_get_type(exc)), MP_OBJ_FROM_PTR(&mp_type_StopIteration))
        || exc == MP_OBJ_FROM_PTR(&mp_const_GeneratorExit_obj)) {
        return;
    }

    // Walk the shadow stack to check if there is an active exception handler in any frame
    bool is_caught = false;
    for (int i = 0; i < shadow_top; i++) {
        const mp_code_state_t *cs = (const mp_code_state_t *)shadow[i].cs;
        if (cs != NULL && cs->exc_sp_idx > 0) {
            is_caught = true;
            break;
        }
    }

    // Also check the current/incoming code state
    if (code_state != NULL && code_state->exc_sp_idx > 0) {
        is_caught = true;
    }

    if (is_caught) {
        return;
    }

    // Format exception into a string (e.g. "ValueError: invalid index")
    vstr_t vstr;
    mp_print_t print;
    vstr_init_print(&vstr, 128, &print);
    mp_obj_print_helper(&print, exc, PRINT_EXC);
    
    const char *exc_str = vstr_null_terminated_str(&vstr);
    size_t exc_len = vstr_len(&vstr);
    if (exc_len > 250) {
        exc_len = 250;
    }

    // Push 0x04 frame: AA 04 len ip_lo ip_hi msg
    const byte *bc_start = code_state->fun_bc->bytecode;
    uint32_t off = (uint32_t)(code_state->ip - bc_start);
    uint16_t off16 = (off > 0xFFFF) ? 0xFFFF : (uint16_t)off;

    dbg_push(0xAA);
    dbg_push(0x04);
    dbg_push((uint8_t)(2 + exc_len));
    dbg_push((uint8_t)(off16 & 0xFF));
    dbg_push((uint8_t)(off16 >> 8));
    for (size_t i = 0; i < exc_len; i++) {
        dbg_push(exc_str[i]);
    }
    vstr_clear(&vstr);

    // Save paused debug state
    paused_fun_bc = (const void *)code_state->fun_bc;
    paused_code_state = code_state;
    paused_ip_off = off16;
    paused_shadow_top = shadow_top;
    for (int i = 0; i < shadow_top; i++) {
        paused_shadow[i] = shadow[i];
    }

    mp_dbg_paused = 1;
    MP_DBG_BARRIER();

    // Busy-wait until host debug bridge resumes execution
    while (mp_dbg_paused) {
        MP_DBG_BARRIER();
        mp_hal_delay_ms(1);
        mp_handle_pending(true);
    }
}

"""

if old_anchor not in s_c:
    raise SystemExit("FAIL: m_trace_on anchor not found in moddbg.c")
s_c = s_c.replace(old_anchor, impl + "\n" + old_anchor, 1)
open(p_c, "w").write(s_c)

# 3. Modify py/vm.c
p_v = mpy_dir + "/py/vm.c"
s_v = open(p_v).read()

old_exc_handler = """        } else {
exception_handler:
            // exception occurred"""

new_exc_handler = """        } else {
exception_handler:
            // exception occurred
            mp_dbg_handle_exception(MP_OBJ_FROM_PTR(nlr.ret_val), code_state);"""

if old_exc_handler not in s_v:
    raise SystemExit("FAIL: exception_handler label not found in vm.c")
s_v = s_v.replace(old_exc_handler, new_exc_handler, 1)
open(p_v, "w").write(s_v)

PY

grep -q 'mp_dbg_handle_exception' "$MPY_DIR/py/moddbg.h" || { echo "FAIL: moddbg.h exception missing"; exit 1; }
grep -q 'mp_dbg_handle_exception' "$MPY_DIR/py/moddbg.c" || { echo "FAIL: moddbg.c exception missing"; exit 1; }
grep -q 'mp_dbg_handle_exception' "$MPY_DIR/py/vm.c"     || { echo "FAIL: vm.c exception hook missing"; exit 1; }
echo "    0021 applied OK"
