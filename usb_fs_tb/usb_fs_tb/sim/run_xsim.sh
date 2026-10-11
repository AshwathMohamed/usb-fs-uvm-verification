#!/bin/bash
# Vivado xsim version (not tested, see README). Needs Vivado in your PATH.
#   ./run_xsim.sh usb_rand_test
cd "$(dirname "$0")" || exit 1
T=${1:-usb_rand_test}

rm -rf xsim.dir
{ echo "simulator: Vivado xsim"; echo "seed: not set"; } > run_info.txt
xvlog -sv -L uvm -i ../tb -i ../tests -f files.f || exit 1
xelab -L uvm -timescale 1ns/1ps work.tb_top -s sim_$T -debug typical || exit 1
xsim sim_$T -runall -testplusarg UVM_TESTNAME=$T -log log_$T.txt
./summarize.sh
