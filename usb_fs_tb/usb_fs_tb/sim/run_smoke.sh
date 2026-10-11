#!/bin/bash
# Small test without UVM (tb/smoke_tb.sv). Needs Verilator.
# In Questa instead:  vlog -sv -f files_smoke.f ; vsim -c smoke_tb -do "run -all; quit" | tee smoke_run.log
cd "$(dirname "$0")" || exit 1
verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style -Wno-TIMESCALEMOD \
  --top-module smoke_tb --Mdir obj_smoke \
  ../rtl/usb_pkg.sv ../tb/usb_ref_pkg.sv ../rtl/usb_tx.sv ../rtl/usb_rx.sv ../rtl/usb_top.sv ../tb/smoke_tb.sv \
  > smoke_build.log 2>&1 || { echo "build failed, see sim/smoke_build.log"; exit 1; }
./obj_smoke/Vsmoke_tb | tee smoke_run.log
