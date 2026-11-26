#!/usr/bin/env bash
# A resume/step request must exit the current VM hook before another pause.
set -euo pipefail
MPY_DIR="${MPY_DIR:-$HOME/micropython}"
export MPY_DIR
python3 - <<'PY'
import os
from pathlib import Path
p = Path(os.environ["MPY_DIR"]) / "py" / "moddbg.c"
s = p.read_text()
start = s.index("void mp_dbg_hook(")
end = s.index("// ---- Python API", start)
hook = s[start:end]
# Existing patches promote pending step-in after each pause. Return there
# instead of evaluating a subsequent step handler on the same opcode.
promote = "if (mp_dbg_stepping_in_pending) { mp_dbg_stepping_in = 1; mp_dbg_stepping_in_pending = 0; }"
old = promote + "\n                break;"
if hook.count(old) != 1:
    raise SystemExit("FAIL: unexpected breakpoint pause continuation")
hook = hook.replace(old, promote + "\n                return;", 1)
old = promote + "\n    }"
if hook.count(old) != 2:
    raise SystemExit("FAIL: unexpected step-over/in pause continuation")
hook = hook.replace(old, promote + "\n        return;\n    }")
# Also promote a newly requested step-in when leaving a step-out pause.
# The function naturally returns at its end.
step_out = hook.index("// --- step-out")
tail = hook[step_out:]
if promote not in tail:
    import re
    # Match the busy wait in the final step-out branch, not an earlier loop.
    pattern = r"(while \(mp_dbg_paused\) \{\s*MP_DBG_BARRIER\(\);\s*mp_hal_delay_ms\(1\);\s*mp_handle_pending\(true\);\s*\})"
    tail, count = re.subn(pattern, r"\1" + "\n        " + promote, tail)
    if count != 1:
        raise SystemExit("FAIL: unexpected step-out pause continuation")
    hook = hook[:step_out] + tail
p.write_text(s[:start] + hook + s[end:])
PY
echo "    0022 applied OK"
