#!/usr/bin/env bash
# Patch 0019 — Include function identity in breakpoint-hit events
#
# Old event:
#   type 0x02 payload: ip_off:u16
#
# New event:
#   type 0x02 payload: ip_off:u16 + fun_ptr:u32
#
# This disambiguates breakpoints in different functions that happen to use the
# same bytecode offset. Studio remains backward-compatible with the old 2-byte
# payload.

set -euo pipefail
MPY_DIR="${MPY_DIR:-$HOME/micropython}"

python3 - <<'PY'
import os
p = os.path.expanduser(os.environ.get("MPY_DIR", "~/micropython")) + "/py/moddbg.c"
s = open(p).read()

old = """static inline void emit_bp_hit(uint16_t ip_off) {
    dbg_push(0xAA); dbg_push(0x02); dbg_push(2);
    dbg_push((uint8_t)(ip_off & 0xFF));
    dbg_push((uint8_t)(ip_off >> 8));
}"""
new = """static inline void emit_bp_hit(uint16_t ip_off, const void *fun_bc) {
    uint32_t fun = (uint32_t)(uintptr_t)fun_bc;
    dbg_push(0xAA); dbg_push(0x02); dbg_push(6);
    dbg_push((uint8_t)(ip_off & 0xFF));
    dbg_push((uint8_t)(ip_off >> 8));
    dbg_push((uint8_t)(fun & 0xFF));
    dbg_push((uint8_t)((fun >> 8) & 0xFF));
    dbg_push((uint8_t)((fun >> 16) & 0xFF));
    dbg_push((uint8_t)((fun >> 24) & 0xFF));
}"""
if old not in s:
    raise SystemExit("FAIL: emit_bp_hit definition not found")
s = s.replace(old, new, 1)

count = s.count("emit_bp_hit(off16);")
if count == 0:
    raise SystemExit("FAIL: no breakpoint hit call sites found")
s = s.replace(
    "emit_bp_hit(off16);",
    "emit_bp_hit(off16, (const void *)code_state->fun_bc);"
)

open(p, "w").write(s)
print("updated", count, "emit_bp_hit call sites")
PY

grep -q 'dbg_push(0xAA); dbg_push(0x02); dbg_push(6);' "$MPY_DIR/py/moddbg.c" || { echo "FAIL: bp_hit length"; exit 1; }
grep -q 'emit_bp_hit(off16, (const void \*)code_state->fun_bc);' "$MPY_DIR/py/moddbg.c" || { echo "FAIL: bp_hit function id"; exit 1; }

echo "    0019 applied OK"
