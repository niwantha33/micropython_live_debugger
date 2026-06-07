#!/usr/bin/env bash
# Patch 0019 — Frame-relative scope navigation
#
# Adds depth support to:
#   dbg.locals(depth=0)
#   dbg.poke(slot_idx, value, depth=0)
#   dbg.globals(depth=0)

set -euo pipefail
MPY_DIR="${MPY_DIR:-$HOME/micropython}"

python3 - <<'PY'
import os
p = os.path.expanduser(os.environ.get("MPY_DIR", "~/micropython")) + "/py/moddbg.c"
s = open(p).read()

# 1) Replace m_locals definition
old_locals = """static mp_obj_t m_locals(void) {
    if (!mp_dbg_paused || paused_code_state == NULL) return mp_const_none;
    size_t n = paused_code_state->n_state;
    mp_obj_t list = mp_obj_new_list(0, NULL);
    for (size_t i = 0; i < n; i++) {
        mp_obj_t v = paused_code_state->state[i];
        if (v == MP_OBJ_NULL) v = mp_const_none;
        mp_obj_list_append(list, v);
    }
    return list;
}
static MP_DEFINE_CONST_FUN_OBJ_0(m_locals_obj, m_locals);"""

new_locals = """static mp_obj_t m_locals(size_t n_args, const mp_obj_t *args) {
    if (!mp_dbg_paused || paused_code_state == NULL) {
        return mp_const_none;
    }
    mp_int_t depth = 0;
    if (n_args > 0) {
        depth = mp_obj_get_int(args[0]);
    }
    if (depth < 0 || depth >= paused_shadow_top) {
        mp_raise_ValueError(MP_ERROR_TEXT("invalid frame depth"));
    }
    int target_idx = paused_shadow_top - 1 - depth;
    const mp_code_state_t *cs = (const mp_code_state_t *)paused_shadow[target_idx].cs;
    if (cs == NULL) {
        return mp_const_none;
    }
    size_t n = cs->n_state;
    mp_obj_t list = mp_obj_new_list(0, NULL);
    for (size_t i = 0; i < n; i++) {
        mp_obj_t v = cs->state[i];
        if (v == MP_OBJ_NULL) v = mp_const_none;
        mp_obj_list_append(list, v);
    }
    return list;
}
static MP_DEFINE_CONST_FUN_OBJ_VAR_BETWEEN(m_locals_obj, 0, 1, m_locals);"""

if old_locals not in s: raise SystemExit("FAIL: old_locals not found")
s = s.replace(old_locals, new_locals, 1)

# 2) Replace m_poke and m_globals definitions
old_poke_globals = """static mp_obj_t m_poke(mp_obj_t index_in, mp_obj_t value_in) {
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

new_poke_globals = """static mp_obj_t m_poke(size_t n_args, const mp_obj_t *args) {
    if (!mp_dbg_paused || paused_code_state == NULL) {
        return mp_const_false;
    }
    mp_int_t index = mp_obj_get_int(args[0]);
    mp_obj_t value_in = args[1];
    mp_int_t depth = 0;
    if (n_args > 2) {
        depth = mp_obj_get_int(args[2]);
    }
    if (depth < 0 || depth >= paused_shadow_top) {
        mp_raise_ValueError(MP_ERROR_TEXT("invalid frame depth"));
    }
    int target_idx = paused_shadow_top - 1 - depth;
    mp_code_state_t *cs = (mp_code_state_t *)paused_shadow[target_idx].cs;
    if (cs == NULL) {
        return mp_const_false;
    }
    if (index < 0 || (size_t)index >= cs->n_state) {
        mp_raise_ValueError(MP_ERROR_TEXT("slot index out of range"));
    }
    cs->state[index] = value_in;
    MP_DBG_BARRIER();
    return mp_const_true;
}
static MP_DEFINE_CONST_FUN_OBJ_VAR_BETWEEN(m_poke_obj, 2, 3, m_poke);

static mp_obj_t m_globals(size_t n_args, const mp_obj_t *args) {
    if (!mp_dbg_paused || paused_code_state == NULL) {
        return mp_const_none;
    }
    mp_int_t depth = 0;
    if (n_args > 0) {
        depth = mp_obj_get_int(args[0]);
    }
    if (depth < 0 || depth >= paused_shadow_top) {
        mp_raise_ValueError(MP_ERROR_TEXT("invalid frame depth"));
    }
    int target_idx = paused_shadow_top - 1 - depth;
    const mp_obj_fun_bc_t *fun = (const mp_obj_fun_bc_t *)paused_shadow[target_idx].fun_bc;
    if (fun == NULL || !mp_obj_is_type(MP_OBJ_FROM_PTR(fun), &mp_type_fun_bc)) {
        return mp_const_none;
    }
    if (fun->context == NULL) {
        return mp_const_none;
    }
    return MP_OBJ_FROM_PTR(fun->context->module.globals);
}
static MP_DEFINE_CONST_FUN_OBJ_VAR_BETWEEN(m_globals_obj, 0, 1, m_globals);"""

if old_poke_globals not in s: raise SystemExit("FAIL: old_poke_globals not found")
s = s.replace(old_poke_globals, new_poke_globals, 1)

open(p, "w").write(s)
PY

grep -q 'MP_DEFINE_CONST_FUN_OBJ_VAR_BETWEEN(m_locals_obj' "$MPY_DIR/py/moddbg.c" || { echo "FAIL: m_locals macro missing"; exit 1; }
grep -q 'MP_DEFINE_CONST_FUN_OBJ_VAR_BETWEEN(m_poke_obj' "$MPY_DIR/py/moddbg.c" || { echo "FAIL: m_poke macro missing"; exit 1; }
grep -q 'MP_DEFINE_CONST_FUN_OBJ_VAR_BETWEEN(m_globals_obj' "$MPY_DIR/py/moddbg.c" || { echo "FAIL: m_globals macro missing"; exit 1; }
echo "    0019 applied OK"
