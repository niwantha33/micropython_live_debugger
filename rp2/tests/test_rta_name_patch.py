"""Regression for RTA name patch: the BP and RTA encoders share a declaration.

CI applies the real patch to a temporary synthetic moddbg.c, without
modifying any flashed image, working MicroPython tree or user boot.py.
"""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
PATCH = ROOT / "firmware/patches/0020-rta-function-name-replies.sh"

# Matches the two separate local declarations installed by patches 0018 and 0019.
# The pre-fix patch failed because it matched BOTH declarations.
SOURCE = """#include "py/moddbg.h"
static inline void emit_bp_hit(uint16_t ip_off, const void *fun_bc) {
    uint32_t fun = (uint32_t)(uintptr_t)fun_bc;
    dbg_push(0xAA);
}
static inline void emit_rta_segment(uint8_t type, const void *fun_bc, uint32_t ts_us) {
    uint32_t fun = (uint32_t)(uintptr_t)fun_bc;
    dbg_push(0xAA);
    dbg_push(type);
    dbg_push(8);
}
void sample_hook(void) {
            emit_rta_segment(0x05, cur_fun_bc, now_us);
}
static mp_obj_t m_rta_on(void) {
    rta_last_code_state = NULL;
    return mp_const_none;
}
"""


class RtaNamePatchTest(unittest.TestCase):
    def test_rta_capacity_check_is_scoped_and_patch_is_idempotent(self):
        with tempfile.TemporaryDirectory() as root:
            py = Path(root) / "py"
            py.mkdir()
            cfile = py / "moddbg.c"
            cfile.write_text(SOURCE)
            env = {**os.environ, "MPY_DIR": root}

            for attempt in (1, 2):
                result = subprocess.run(
                    ["bash", str(PATCH)], env=env,
                    capture_output=True, text=True, check=False,
                )
                self.assertEqual(
                    result.returncode, 0,
                    "patch run %d failed:\n%s\n%s" % (
                        attempt, result.stdout, result.stderr,
                    ),
                )
                contents = cfile.read_text()
                self.assertEqual(contents.count("rta_ring_can_write(11)"), 1)
                self.assertIn(
                    "static inline void emit_bp_hit(uint16_t ip_off, const void *fun_bc) {\n"
                    "    uint32_t fun = (uint32_t)(uintptr_t)fun_bc;",
                    contents,
                )
                self.assertIn(
                    "static inline void emit_rta_segment(uint8_t type, const void *fun_bc, uint32_t ts_us) {\n"
                    "    if (!rta_ring_can_write(11)) { dbg_lost += 11; return; }\n"
                    "    uint32_t fun = (uint32_t)(uintptr_t)fun_bc;",
                    contents,
                )
                self.assertEqual(contents.count("rta_emit_symbol_if_new(cur_fun_bc);"), 1)


if __name__ == "__main__":
    unittest.main()
