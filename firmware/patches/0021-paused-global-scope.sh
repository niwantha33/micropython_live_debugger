#!/usr/bin/env bash
# Read globals from the actual paused bytecode function, never the pump VM.
set -euo pipefail
MPY_DIR="${MPY_DIR:-$HOME/micropython}"
export MPY_DIR
python3 - <<'PY'
import os
from pathlib import Path
path = Path(os.environ["MPY_DIR"]) / "py" / "moddbg.c"
source = path.read_text()
anchor = "static const mp_rom_map_elem_t dbg_module_globals_table[] = {"
if source.count(anchor) != 1 or "m_globals_obj" in source:
    raise SystemExit("Unexpected globals API or module registration")
if "paused_code_state" not in source or '#include "py/objfun.h"' not in source:
    raise SystemExit("Missing paused-frame or function definitions")
helper = """
// Depth zero must use the exact paused VM state, not the shadow stack,
// which may contain debugger-thread frames. Do not claim deeper frames.
static mp_obj_t m_globals(size_t n_args, const mp_obj_t *args) {
    mp_int_t depth = n_args ? mp_obj_get_int(args[0]) : 0;
    if (depth != 0) {
        mp_raise_ValueError(MP_ERROR_TEXT("global scope depth unsupported"));
    }
    if (!mp_dbg_paused || paused_code_state == NULL) {
        return mp_const_none;
    }
    MP_DBG_BARRIER();
    const mp_obj_fun_bc_t *fun = paused_code_state->fun_bc;
    if (fun == NULL || fun->context == NULL || fun->context->module.globals == NULL) {
        return mp_const_none;
    }
    return MP_OBJ_FROM_PTR(fun->context->module.globals);
}
static MP_DEFINE_CONST_FUN_OBJ_VAR_BETWEEN(m_globals_obj, 0, 1, m_globals);
"""
source = source.replace(anchor, helper + "\n" + anchor +
                        "\n    { MP_ROM_QSTR(MP_QSTR_globals), MP_ROM_PTR(&m_globals_obj) },", 1)
path.write_text(source)
PY
echo "    0021 applied OK"
