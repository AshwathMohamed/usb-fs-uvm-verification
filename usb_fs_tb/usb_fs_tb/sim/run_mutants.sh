#!/bin/bash
# Breaks the RTL on purpose (in a temp copy) and checks that smoke_tb notices.
# Every mutant should show fail > 0. If one shows fail=0, the test has a hole.
# Needs Verilator.
cd "$(dirname "$0")" || exit 1
T=$(mktemp -d)

run() {   # $1 = what we broke
  verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style -Wno-TIMESCALEMOD \
    --top-module smoke_tb --Mdir $T/obj $T/usb_pkg.sv ../tb/usb_ref_pkg.sv $T/usb_tx.sv $T/usb_rx.sv $T/usb_top.sv ../tb/smoke_tb.sv >/dev/null 2>&1
  echo "$1 -> $($T/obj/Vsmoke_tb 2>&1 | grep 'SMOKE RESULT')"
}
fresh() { cp ../rtl/*.sv $T/; }

fresh;                                                                   run "no mutation (should be fail=0)"
fresh; sed -i "s/5'h05;/5'h15;/"      $T/usb_pkg.sv;                     run "wrong CRC5 polynomial"
fresh; sed -i "s/16'h8005;/16'h8003;/" $T/usb_pkg.sv;                    run "wrong CRC16 polynomial"
fresh; sed -i "s/if (ones == 6) expect_stuff = 1;/if (ones == 7) expect_stuff = 1;/" $T/usb_rx.sv; run "rx un-stuffs after 7 ones"
fresh; sed -i "s/pid_sh\\[7:4\\] != ~pid_sh\\[3:0\\]/1'b0/" $T/usb_rx.sv;    run "rx never flags pid_err"
fresh; sed -i "s/if (!out_bit) line_j <= ~line_j;/if (out_bit) line_j <= ~line_j;/" $T/usb_tx.sv; run "NRZI inverted in tx"
rm -rf $T
