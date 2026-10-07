#!/usr/bin/env bash
# Patch 0018 — Real-Time Analysis (RTA) execution-segment events
#
# Adds:
#   dbg.rta_on() / dbg.rta_off()
#   firmware->host event 0x05 = RTA enter, payload fun_ptr:u32 + ticks_us:u32
#   firmware->host event 0x06 = RTA exit,  payload fun_ptr:u32 + ticks_us:u32
#
# Semantics:
#   RTA reports VM execution segments, not wall-clock function calls. Whenever
#   execution changes to a different MicroPython code_state, the previous
#   segment is closed and the new one is opened at the same microsecond
#   timestamp. This gives the host an exclusive observed-runtime stream that is
#   suitable for a FreeRTOS-style task/function viewer without double-counting
#   nested Python calls.
#
#   The debugger pump function is excluded. Native blocking time and scheduler
#   idle time are not independently observable yet; exact scheduler CPU% needs
#   a future scheduler-switch hook.
#
# Timestamp wraps at 2^32 microseconds; the host handles rollover.

set -euo pipefail
MPY_DIR="${MPY_DIR:-$HOME/micropython}"

# ---- moddbg.h: expose flag and keep the VM hook active while RTA is on ------
python3 - <<'PY'
import os
p = os.path.expanduser(os.environ.get("MPY_DIR", "~/micropython")) + "/py/moddbg.h"
s = open(p).read()

if "extern volatile uint8_t mp_dbg_rta_enabled;" not in s:
    anchor = "extern volatile uint8_t mp_dbg_stepping_out;"
    if anchor not in s:
        raise SystemExit("FAIL: stepping_out extern anchor not found")
    s = s.replace(anchor, anchor + "\nextern volatile uint8_t mp_dbg_rta_enabled;", 1)

old = "|| mp_dbg_stepping || mp_dbg_stepping_in || mp_dbg_stepping_out)"
new = "|| mp_dbg_stepping || mp_dbg_stepping_in || mp_dbg_stepping_out || (mp_dbg_rta_enabled && !mp_dbg_muted))"
if old in s:
    s = s.replace(old, new, 1)
elif "mp_dbg_rta_enabled && !mp_dbg_muted" not in s:
    raise SystemExit("FAIL: MP_DBG_HOOK gate anchor not found")

open(p, "w").write(s)
PY

# ---- moddbg.c: event encoding, segment tracker, Python API -------------------
python3 - <<'PY'
import os
p = os.path.expanduser(os.environ.get("MPY_DIR", "~/micropython")) + "/py/moddbg.c"
s = open(p).read()

# 1) State. Keep this separate from the existing debugger shadow stack because
# RTA wants execution segments, not a synthetic call-stack snapshot.
if "volatile uint8_t mp_dbg_rta_enabled = 0;" not in s:
    anchor = "volatile uint8_t mp_dbg_stepping_out = 0;"
    if anchor not in s:
        raise SystemExit("FAIL: stepping_out definition anchor not found")
    state = """volatile uint8_t mp_dbg_rta_enabled = 0;
static const void *rta_last_code_state = NULL;
static const void *rta_last_fun_bc = NULL;"""
    s = s.replace(anchor, anchor + "\n" + state, 1)

# 2) Framed RTA event helper.
if "emit_rta_segment" not in s:
    anchor = "void mp_dbg_hook(const byte *ip, const mp_code_state_t *code_state) {"
    if anchor not in s:
        raise SystemExit("FAIL: mp_dbg_hook anchor not found")
    helper = r"""
static inline void emit_rta_segment(uint8_t type, const void *fun_bc, uint32_t ts_us) {
    uint32_t fun = (uint32_t)(uintptr_t)fun_bc;
    dbg_push(0xAA);
    dbg_push(type);
    dbg_push(8);
    dbg_push((uint8_t)(fun & 0xFF));
    dbg_push((uint8_t)((fun >> 8) & 0xFF));
    dbg_push((uint8_t)((fun >> 16) & 0xFF));
    dbg_push((uint8_t)((fun >> 24) & 0xFF));
    dbg_push((uint8_t)(ts_us & 0xFF));
    dbg_push((uint8_t)((ts_us >> 8) & 0xFF));
    dbg_push((uint8_t)((ts_us >> 16) & 0xFF));
    dbg_push((uint8_t)((ts_us >> 24) & 0xFF));
}

"""
    s = s.replace(anchor, helper + anchor, 1)

# 3) Emit an EXIT/ENTER pair whenever execution moves to a new code_state.
# pump_fun_bc exists by patch 0011. The pump remains invisible to RTA.
marker = "    // --- shadow stack update ---"
if "RTA execution-segment switch" not in s:
    if marker not in s:
        raise SystemExit("FAIL: shadow stack marker not found")
    rta = r"""    // --- RTA execution-segment switch ---
    if (mp_dbg_rta_enabled && !mp_dbg_muted
        && (const void *)code_state->fun_bc != pump_fun_bc) {
        const void *cur_code_state = (const void *)code_state;
        const void *cur_fun_bc = (const void *)code_state->fun_bc;
        if (cur_code_state != rta_last_code_state) {
            uint32_t now_us = (uint32_t)mp_hal_ticks_us();
            if (rta_last_code_state != NULL && rta_last_fun_bc != NULL) {
                emit_rta_segment(0x06, rta_last_fun_bc, now_us);
            }
            emit_rta_segment(0x05, cur_fun_bc, now_us);
            rta_last_code_state = cur_code_state;
            rta_last_fun_bc = cur_fun_bc;
        }
    }

"""
    s = s.replace(marker, rta + marker, 1)

# 4) Python control API. RTA OFF deliberately stops emission before clearing
# state so the pump core does not become a second producer of ring events.
if "m_rta_on_obj" not in s:
    g_anchor = "static const mp_rom_map_elem_t dbg_module_globals_table[] = {"
    if g_anchor not in s:
        raise SystemExit("FAIL: globals table anchor not found")
    api = r"""
static mp_obj_t m_rta_on(void) {
    rta_last_code_state = NULL;
    rta_last_fun_bc = NULL;
    MP_DBG_BARRIER();
    mp_dbg_rta_enabled = 1;
    MP_DBG_BARRIER();
    return mp_const_none;
}
static MP_DEFINE_CONST_FUN_OBJ_0(m_rta_on_obj, m_rta_on);

static mp_obj_t m_rta_off(void) {
    mp_dbg_rta_enabled = 0;
    MP_DBG_BARRIER();
    rta_last_code_state = NULL;
    rta_last_fun_bc = NULL;
    return mp_const_none;
}
static MP_DEFINE_CONST_FUN_OBJ_0(m_rta_off_obj, m_rta_off);

"""
    s = s.replace(g_anchor, api + g_anchor, 1)

# 5) Module exports.
if "MP_QSTR_rta_on" not in s:
    anchor = "    { MP_ROM_QSTR(MP_QSTR_trace_off),    MP_ROM_PTR(&m_trace_off_obj) },"
    if anchor not in s:
        raise SystemExit("FAIL: trace_off registration anchor not found")
    regs = (
        anchor
        + "\n    { MP_ROM_QSTR(MP_QSTR_rta_on),       MP_ROM_PTR(&m_rta_on_obj) },"
        + "\n    { MP_ROM_QSTR(MP_QSTR_rta_off),      MP_ROM_PTR(&m_rta_off_obj) },"
    )
    s = s.replace(anchor, regs, 1)

open(p, "w").write(s)
PY

grep -q 'mp_dbg_rta_enabled' "$MPY_DIR/py/moddbg.h" || { echo "FAIL: RTA header flag"; exit 1; }
grep -q 'm_rta_on_obj' "$MPY_DIR/py/moddbg.c" || { echo "FAIL: rta_on API"; exit 1; }
grep -q 'm_rta_off_obj' "$MPY_DIR/py/moddbg.c" || { echo "FAIL: rta_off API"; exit 1; }
grep -q 'emit_rta_segment(0x05' "$MPY_DIR/py/moddbg.c" || { echo "FAIL: RTA enter event"; exit 1; }
grep -q 'emit_rta_segment(0x06' "$MPY_DIR/py/moddbg.c" || { echo "FAIL: RTA exit event"; exit 1; }

echo "    0018 applied OK"
