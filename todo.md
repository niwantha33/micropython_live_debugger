# Real-Time Analysis (RTA) Trace Verification TODO

- [ ] **Flash Latest Firmware**:
  - Flash `firmware/firmware_pico2_w.uf2` to the board (contains the C-level atomic buffer limit protection check to prevent partial frames).

- [ ] **Run Console & Pump**:
  - Open console: `python host/dbg_console.py COM8` (or correct COM port).
  - Open trace pump in another window if needed, or import/start the trace pump via your script:
    ```python
    import trace_pump
    trace_pump.start()
    ```

- [ ] **Capture RTA Events**:
  - Start capture: `dbg.rta_on()`
  - Let your code run (e.g. `asyncio.run(rts.main())`).
  - Stop capture: `dbg.rta_off()`

- [ ] **Dump & Verify**:
  - In `dbg_console`, run: `rtadump`
  - Ensure the console displays the exact count of saved events and no corrupt packets.
  - Open [ui.perfetto.dev](https://ui.perfetto.dev/) and load the resulting `rta_trace.json` to verify function execution blocks.
