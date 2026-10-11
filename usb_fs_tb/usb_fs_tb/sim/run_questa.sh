#!/bin/bash
# Run the UVM tests in QuestaSim.
#   ./run_questa.sh                 -> run all 5 tests with seed 1, then merge coverage
#   ./run_questa.sh usb_mixed_test  -> run one test
#   ./run_questa.sh all 7           -> run all tests with seed 7
# At the end summarize.sh prints the key lines from the logs.
cd "$(dirname "$0")" || exit 1

TESTS="usb_rand_test usb_crc_err_test usb_pid_err_test usb_stuff_err_test usb_mixed_test"
WHICH=${1:-all}
SEED=${2:-1}
[ "$WHICH" = "all" ] || TESTS=$WHICH

rm -rf work cov_*.ucdb log_*.txt merged.ucdb
vlib work || exit 1
{ echo "simulator: $(vsim -version 2>&1 | head -1)"; echo "seed: $SEED"; } > run_info.txt

# If vlog cannot find uvm_pkg, remove "-L mtiUvm" and use your UVM source instead, e.g.
#   vlog -sv +incdir+$UVM_HOME/src $UVM_HOME/src/uvm_pkg.sv ...
vlog -sv -L mtiUvm -timescale 1ns/1ps +incdir+../tb +incdir+../tests -f files.f -l log_compile.txt || exit 1

for T in $TESTS; do
  echo "=== running $T (seed $SEED) ==="
  vsim -c -coverage -sv_seed $SEED -L mtiUvm work.tb_top +UVM_TESTNAME=$T \
       -do "coverage save -onexit -assert -directive -cvg cov_$T.ucdb; run -all; quit -f" \
       -l log_$T.txt
done

if ls cov_*.ucdb >/dev/null 2>&1; then
  vcover merge -out merged.ucdb cov_*.ucdb
  vcover report -details -cvg -assert -directive merged.ucdb -output cov_report.txt
  echo "merged coverage report: sim/cov_report.txt"
fi

./summarize.sh
