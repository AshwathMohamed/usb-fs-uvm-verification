#!/bin/bash
# Prints the key lines from the simulation logs (PASS/FAIL, packet counts, coverage, SVA).
cd "$(dirname "$0")" || exit 1
TESTS="usb_rand_test usb_crc_err_test usb_pid_err_test usb_stuff_err_test usb_mixed_test"

# field "<line>" name  -> the number after name=
field() { echo "$1" | sed -nE "s/.*$2=([0-9.]+).*/\1/p"; }

{
  echo "### Simulation results"
  echo
  [ -f run_info.txt ] && sed 's/^/- /' run_info.txt
  echo "- date: $(date +%F)"
  echo
  echo "| Test | Packets checked | Passed | Failed | UVM errors | Verdict |"
  echo "|---|---|---|---|---|---|"
  for t in $TESTS; do
    log=log_$t.txt
    [ -f "$log" ] || continue
    line=$(grep -h "RESULT checked" "$log" | tail -1)
    errs=$(grep -h "UVM_ERROR :" "$log" | tail -1 | awk '{print $NF}')
    verdict=$(grep -h -o -E "TEST (PASSED|FAILED)" "$log" | tail -1)
    echo "| $t | $(field "$line" checked) | $(field "$line" passed) | $(field "$line" failed) | ${errs:-?} | ${verdict:-no verdict} |"
  done

  echo
  echo "Functional coverage per test (from the COVERAGE line of each log):"
  echo
  echo "| Test | Packet type | Data length | Error type | Type x error | Total |"
  echo "|---|---|---|---|---|---|"
  for t in $TESTS; do
    log=log_$t.txt
    [ -f "$log" ] || continue
    line=$(grep -h "COVERAGE packet_type" "$log" | tail -1)
    echo "| $t | $(field "$line" packet_type)% | $(field "$line" data_len)% | $(field "$line" error_type)% | $(field "$line" type_x_error)% | $(field "$line" total)% |"
  done

  echo
  echo "SVA (SVA_SUMMARY line of each log):"
  echo
  echo '```'
  for t in $TESTS; do
    [ -f log_$t.txt ] && echo "$t: $(grep -h SVA_SUMMARY log_$t.txt | tail -1 | sed 's/.*SVA_SUMMARY //')"
  done
  echo '```'

  if [ -f cov_report.txt ]; then
    echo
    echo "Merged over all tests (lines picked from sim/cov_report.txt, see that file for the full report):"
    echo
    echo '```'
    grep -i -E "TOTAL|covergroup|coverpoint|cross|a_tx_pid_check|a_rx_pid_check|a_max_six_ones|c_six_ones|c_seven_ones|c_bad_pid_sent" cov_report.txt | head -80
    echo '```'
  fi

  if [ -f smoke_run.log ]; then
    echo
    echo "Smoke test (no UVM): $(grep -h 'SMOKE RESULT' smoke_run.log | tail -1)"
  fi
}
