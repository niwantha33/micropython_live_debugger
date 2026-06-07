#!/usr/bin/env bash
# Patch 0018 — Poke/Mutate variables and get globals dict
#
# Adds:
#   dbg.poke(slot_idx, value) -> bool
#   dbg.globals() -> dict or None
#
# Mutates paused frame state or returns current module globals.

set -euo pipefail
MPY_DIR="${MPY_DIR:-$HOME/micropython}"

python3 - <<'PY'
import os
p = os.path.expanduser(os.environ.get("MPY_DIR", "~/micropython")) + "/py/moddbg.c"
s = open(p).read()

# Add m_poke and m_globals after m_frame_info_obj
old = "static MP_DEFINE_CONST_FUN_OBJ_0(m_frame_info_obj, m_frame_info);"
new = old + """

static mp_obj_t m_poke(mp_obj_t index_in, mp_obj_t value_in) {
    if (!mp_dbg_paused || paused_code_state == NULL) {
        return mp_const_false;
    }
    mp_int_t index = mp_obj_get_int(index_in);
    if (index < 0 || (size_t)index >= paused_code_state->n_state) {
        mp_raise_ValueError(MP_ERROR_TEXT("slot index out of range"));
    }
    ((mp_code_state_t *)paused_code_state)->state[index] = value_in;
    MP_DBG_BARRIER();
    return mp_const_true;
}
static MP_DEFINE_CONST_FUN_OBJ_2(m_poke_obj, m_poke);

static mp_obj_t m_globals(void) {
    if (!mp_dbg_paused || paused_code_state == NULL) {
        return mp_const_none;
    }
    const mp_obj_fun_bc_t *fun = (const mp_obj_fun_bc_t *)paused_code_state->fun_bc;
    if (fun == NULL || !mp_obj_is_type(MP_OBJ_FROM_PTR(fun), &mp_type_fun_bc)) {
        return mp_const_none;
    }
    if (fun->context == NULL) {
        return mp_const_none;
    }
    return MP_OBJ_FROM_PTR(fun->context->module.globals);
}
static MP_DEFINE_CONST_FUN_OBJ_0(m_globals_obj, m_globals);"""

if old not in s: raise SystemExit("FAIL: frame_info anchor missing")
if "m_poke" not in s:
    s = s.replace(old, new, 1)

# Register in globals table
old_reg = "    { MP_ROM_QSTR(MP_QSTR_frame_info),   MP_ROM_PTR(&m_frame_info_obj) },"
new_reg = old_reg + """
    { MP_ROM_QSTR(MP_QSTR_poke),         MP_ROM_PTR(&m_poke_obj) },
    { MP_ROM_QSTR(MP_QSTR_globals),      MP_ROM_PTR(&m_globals_obj) },"""

if old_reg not in s: raise SystemExit("FAIL: frame_info reg not found")
if "MP_QSTR_poke" not in s:
    s = s.replace(old_reg, new_reg, 1)

open(p, "w").write(s)
PY

grep -q 'm_poke_obj' "$MPY_DIR/py/moddbg.c" || { echo "FAIL: m_poke missing"; exit 1; }
grep -q 'm_globals_obj' "$MPY_DIR/py/moddbg.c" || { echo "FAIL: m_globals missing"; exit 1; }
echo "    0018 applied OK"
