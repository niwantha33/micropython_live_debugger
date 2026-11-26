#!/usr/bin/env bash
# Expose an immutable native identity for the scope + step qualification fix.
set -euo pipefail
MPY_DIR="${MPY_DIR:-$HOME/micropython}"
export MPY_DIR
python3 - <<'PY'
import os
from pathlib import Path
p = Path(os.environ["MPY_DIR"]) / "py" / "moddbg.c"
s = p.read_text()
anchor = "static const mp_rom_map_elem_t dbg_module_globals_table[] = {"
if s.count(anchor) != 1 or "m_scope_step_revision_obj" in s:
    raise SystemExit("FAIL: unexpected debugger module registration")
if "m_globals_obj" not in s:
    raise SystemExit("FAIL: paused globals patch missing")
hook = s[s.index("void mp_dbg_hook("):s.index("// ---- Python API")]
if hook.count("mp_dbg_stepping_in_pending = 0; }\n        return;") != 2:
    raise SystemExit("FAIL: step-over/in continuation missing")
if "mp_dbg_stepping_in_pending = 0; }\n                return;" not in hook:
    raise SystemExit("FAIL: breakpoint continuation missing")
helper = """
static mp_obj_t m_scope_step_revision(void) {
    return MP_OBJ_NEW_SMALL_INT(1);
}
static MP_DEFINE_CONST_FUN_OBJ_0(m_scope_step_revision_obj, m_scope_step_revision);
"""
s = s.replace(anchor, helper + "\n" + anchor +
              "\n    { MP_ROM_QSTR(MP_QSTR_scope_step_revision), MP_ROM_PTR(&m_scope_step_revision_obj) },", 1)
p.write_text(s)
PY
echo "    0023 applied OK"
