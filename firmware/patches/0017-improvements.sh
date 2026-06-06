#!/usr/bin/env bash
# Patch 0017 — Thread safety, memory barriers, stack pointer safety, and recursive step-out fix

set -euo pipefail
MPY_DIR="${MPY_DIR:-$HOME/micropython}"

# 1) Modify py/moddbg.h to add MP_DBG_BARRIER macro definition
python3 - <<'PY'
import os
p = os.path.expanduser(os.environ.get("MPY_DIR", "~/micropython")) + "/py/moddbg.h"
s = open(p).read()

barrier_def = """
#if defined(__arm__) || defined(__thumb__)
#define MP_DBG_BARRIER() __asm__ volatile ("dmb" : : : "memory")
#elif defined(__xtensa__)
#define MP_DBG_BARRIER() __asm__ volatile ("memw" : : : "memory")
#else
#define MP_DBG_BARRIER() __asm__ volatile ("" : : : "memory")
#endif
"""

if "MP_DBG_BARRIER()" not in s:
    # Insert before #define MP_DBG_HOOK
    s = s.replace("#define MP_DBG_HOOK(ip, code_state)", barrier_def + "\n#define MP_DBG_HOOK(ip, code_state)")
    open(p, "w").write(s)
PY

# 2) Modify py/moddbg.c to apply barriers, pointer safety, and recursive step-out fix
python3 - <<'PY'
import os
p = os.path.expanduser(os.environ.get("MPY_DIR", "~/micropython")) + "/py/moddbg.c"
s = open(p).read()

# Update step_out_from to be a generic const void *
# Replace while loops inside the hook with MP_DBG_BARRIER() calls
s = s.replace("while (mp_dbg_paused) {", "while (mp_dbg_paused) {\n                    MP_DBG_BARRIER();")
s = s.replace("while (mp_dbg_paused) {\n            mp_hal_delay_ms(1);", "while (mp_dbg_paused) {\n            MP_DBG_BARRIER();\n            mp_hal_delay_ms(1);")

# Update resume, step, step_in, step_out APIs for pointer safety and barriers
old_resume = """static mp_obj_t m_resume(void) {
    mp_dbg_stepping = 0;
    mp_dbg_stepping_in = 0;
    mp_dbg_stepping_in_pending = 0;
    mp_dbg_stepping_out = 0;
    mp_dbg_paused = 0;
    return mp_const_none;
}"""

new_resume = """static mp_obj_t m_resume(void) {
    mp_dbg_stepping = 0;
    mp_dbg_stepping_in = 0;
    mp_dbg_stepping_in_pending = 0;
    mp_dbg_stepping_out = 0;
    paused_code_state = NULL;
    MP_DBG_BARRIER();
    mp_dbg_paused = 0;
    MP_DBG_BARRIER();
    return mp_const_none;
}"""

s = s.replace(old_resume, new_resume)

old_step = """static mp_obj_t m_step(void) {
    mp_dbg_stepping = 1;
    mp_dbg_paused = 0;
    return mp_const_none;
}"""

new_step = """static mp_obj_t m_step(void) {
    mp_dbg_stepping = 1;
    paused_code_state = NULL;
    MP_DBG_BARRIER();
    mp_dbg_paused = 0;
    MP_DBG_BARRIER();
    return mp_const_none;
}"""

s = s.replace(old_step, new_step)

old_step_in = """static mp_obj_t m_step_in(void) {
    mp_dbg_stepping_in_pending = 1;
    mp_dbg_paused = 0;
    return mp_const_none;
}"""

new_step_in = """static mp_obj_t m_step_in(void) {
    mp_dbg_stepping_in_pending = 1;
    paused_code_state = NULL;
    MP_DBG_BARRIER();
    mp_dbg_paused = 0;
    MP_DBG_BARRIER();
    return mp_const_none;
}"""

s = s.replace(old_step_in, new_step_in)

old_step_out = """static mp_obj_t m_step_out(void) {
    step_out_from = paused_fun_bc;
    mp_dbg_stepping_out = 1;
    mp_dbg_paused = 0;
    return mp_const_none;
}"""

new_step_out = """static mp_obj_t m_step_out(void) {
    step_out_from = paused_code_state;
    mp_dbg_stepping_out = 1;
    paused_code_state = NULL;
    MP_DBG_BARRIER();
    mp_dbg_paused = 0;
    MP_DBG_BARRIER();
    return mp_const_none;
}"""

s = s.replace(old_step_out, new_step_out)

# Rewrite the step-out handler inside mp_dbg_hook to check the shadow stack instead of fun_bc comparison
old_step_out_hook = """    // --- step-out (pause when we leave step_out_from frame) ---
    if (mp_dbg_stepping_out && (const void *)code_state->fun_bc != step_out_from && (const void *)code_state->fun_bc != pump_fun_bc) {
        mp_dbg_stepping_out = 0;
        step_out_from = NULL;
        paused_fun_bc = (const void *)code_state->fun_bc;
        paused_code_state = code_state;
        paused_ip_off = off16;
        emit_bp_hit(off16);
        mp_dbg_paused = 1;
        while (mp_dbg_paused) {
            mp_hal_delay_ms(1);
            mp_handle_pending(true);
        }
    }"""

new_step_out_hook = """    // --- step-out (pause when we leave step_out_from frame) ---
    if (mp_dbg_stepping_out && (const void *)code_state->fun_bc != pump_fun_bc) {
        int still_in_stack = 0;
        for (int i = 0; i < shadow_top; i++) {
            if (shadow[i].cs == step_out_from) {
                still_in_stack = 1;
                break;
            }
        }
        if (!still_in_stack) {
            mp_dbg_stepping_out = 0;
            step_out_from = NULL;
            paused_fun_bc = (const void *)code_state->fun_bc;
            paused_code_state = code_state;
            paused_ip_off = off16;
            emit_bp_hit(off16);
            mp_dbg_paused = 1;
            paused_shadow_top = shadow_top;
            for (int _i = 0; _i < shadow_top; _i++) paused_shadow[_i] = shadow[_i];
            while (mp_dbg_paused) {
                MP_DBG_BARRIER();
                mp_hal_delay_ms(1);
                mp_handle_pending(true);
            }
        }
    }"""

s = s.replace(old_step_out_hook, new_step_out_hook)

# 3) Update shadow stack hit handler to refresh fun_bc on matching cs
old_shadow_hit = """        if (found >= 0) {
            shadow_top = (uint8_t)(found + 1);
        }"""

new_shadow_hit = """        if (found >= 0) {
            shadow_top = (uint8_t)(found + 1);
            shadow[found].fun_bc = (const void *)code_state->fun_bc;
        }"""

if old_shadow_hit in s:
    s = s.replace(old_shadow_hit, new_shadow_hit, 1)
else:
    raise SystemExit("FAIL: old_shadow_hit not found")

# 4) Add barriers to m_clear_bp and m_set_bp
old_clear_bp = """static mp_obj_t m_clear_bp(mp_obj_t slot_in) {
    int s = mp_obj_get_int(slot_in);
    if (s < 0 || s >= MAX_BPS) mp_raise_ValueError(MP_ERROR_TEXT("slot"));
    if (bp_table[s].active) {
        bp_table[s].active = 0;
        if (mp_dbg_bp_count > 0) mp_dbg_bp_count--;
    }
    return mp_const_none;
}"""

new_clear_bp = """static mp_obj_t m_clear_bp(mp_obj_t slot_in) {
    int s = mp_obj_get_int(slot_in);
    if (s < 0 || s >= MAX_BPS) mp_raise_ValueError(MP_ERROR_TEXT("slot"));
    if (bp_table[s].active) {
        bp_table[s].active = 0;
        MP_DBG_BARRIER();
        if (mp_dbg_bp_count > 0) {
            mp_dbg_bp_count--;
            MP_DBG_BARRIER();
        }
    }
    return mp_const_none;
}"""

s = s.replace(old_clear_bp, new_clear_bp)

old_set_bp = """static mp_obj_t m_set_bp(mp_obj_t fun_in, mp_obj_t ip_in) {
    const void *fb = (const void *)MP_OBJ_TO_PTR(fun_in);
    uint16_t ipo = (uint16_t)mp_obj_get_int(ip_in);
    for (int i = 0; i < MAX_BPS; i++) {
        if (!bp_table[i].active) {
            bp_table[i].fun_bc = fb;
            bp_table[i].ip_off = ipo;
            bp_table[i].active = 1;
            mp_dbg_bp_count++;
            return mp_obj_new_int(i);
        }
    }
    mp_raise_msg(&mp_type_RuntimeError, MP_ERROR_TEXT("bp table full"));
}"""

new_set_bp = """static mp_obj_t m_set_bp(mp_obj_t fun_in, mp_obj_t ip_in) {
    const void *fb = (const void *)MP_OBJ_TO_PTR(fun_in);
    uint16_t ipo = (uint16_t)mp_obj_get_int(ip_in);
    for (int i = 0; i < MAX_BPS; i++) {
        if (!bp_table[i].active) {
            bp_table[i].fun_bc = fb;
            bp_table[i].ip_off = ipo;
            MP_DBG_BARRIER();
            bp_table[i].active = 1;
            MP_DBG_BARRIER();
            mp_dbg_bp_count++;
            MP_DBG_BARRIER();
            return mp_obj_new_int(i);
        }
    }
    mp_raise_msg(&mp_type_RuntimeError, MP_ERROR_TEXT("bp table full"));
}"""

s = s.replace(old_set_bp, new_set_bp)

open(p, "w").write(s)
PY

echo "    0017 applied OK"
