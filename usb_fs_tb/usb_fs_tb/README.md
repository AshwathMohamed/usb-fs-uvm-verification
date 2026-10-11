# USB 2.0 Full-Speed Packet Layer Testbench

A small SystemVerilog / UVM / SVA project. I built a simple USB 2.0 Full-Speed
packet transmitter and receiver (the DUT) and a UVM testbench that checks it.

The DUT only does the **packet layer**: building and decoding the bit stream.
There is no real D+/D- analog stuff. The line is one J/K signal plus an EOP flag.
One clock = one bit time.

## What is in the DUT

- `usb_tx`: packet in -> SYNC, PID, fields, CRC -> bit stuffing -> NRZI -> EOP.
- `usb_rx`: NRZI decode -> un-stuffing -> PID check -> CRC check -> packet out + error flags
  (`crc_err`, `stuff_err`, `pid_err`).
- `usb_top`: tx and rx connected back to back.
- Packets: token (OUT, IN, SETUP, SOF with CRC5), data (DATA0, DATA1 with CRC16, 0 to 64 bytes),
  handshake (ACK, NAK, STALL, no CRC). Fields are sent LSB first, CRC is sent MSB first.
- CRC5: x^5 + x^2 + 1, CRC16: x^16 + x^15 + x^2 + 1, init all ones, output inverted.
- The tx has error injection inputs: flip a CRC bit, flip a PID check bit, or send a bad stuff bit.

## Folders

```
rtl/      usb_pkg.sv  usb_tx.sv  usb_rx.sv  usb_top.sv
tb/       usb_if.sv (interface + SVA)   usb_ref_pkg.sv (reference model functions)
          usb_item / sequences / driver / monitor / agent / scoreboard / coverage / env
          usb_uvm_pkg.sv   tb_top.sv   smoke_tb.sv (small test without UVM)
tests/    usb_tests.sv  usb_test_pkg.sv
sim/      run_questa.sh  run_xsim.sh  run_smoke.sh  run_mutants.sh  summarize.sh
          check_crc.py (CRC check in Python)  files.f  files_smoke.f
```

## How the testbench works

- **Agent**: sequence item, sequencer, driver, monitor. The driver gives each packet to the DUT.
  The monitor sends two things to the scoreboard: the packet that went into the DUT, and what came
  out (line bits, decoded packet, flags).
- **Reference model** (`tb/usb_ref_pkg.sv`): plain SystemVerilog functions for CRC5, CRC16,
  bit stuffing and NRZI. The CRC is written the "reflected" way (shift right) so it is not a copy of
  the RTL (shift left).
- **Scoreboard**: for every packet it builds the expected line bits and expected error flags with the
  reference model, then compares with the DUT line, the decoded packet and the flags.
- **SVA** (in `tb/usb_if.sv`):
  1. PID check bits are the complement of the PID (`pid[7:4] == ~pid[3:0]`) on valid packets (tx and rx side).
  2. The stuffed stream never has more than six 1s in a row (switched off only for the packet where I
     force a stuffing error on purpose).
  3. Three `cover property` lines to show the checks really see the interesting cases.

  A test also fails if any assertion fails. The log line `SVA_SUMMARY` shows `checked` (how many times
  a check had something to look at) and `fail`.
- **Coverage**: packet type, data length buckets (0, 1-8, 9-32, 33-63, 64), error type, and
  cross of packet type x error type. Handshake x CRC error and handshake x stuffing error can never
  happen (no CRC, no long run of 1s), so those 6 cross bins are ignored.
- **Sequences**: `usb_valid_seq` (random good packets), `usb_err_seq` (one error type on every packet
  type that can have it), `usb_mixed_seq` (random mix of good and bad packets).

## Tests

| Test | What it does | Packets sent |
|---|---|---|
| `usb_rand_test` | Random valid packets of all types, data length 0 to 64 bytes. No errors. | 300 |
| `usb_crc_err_test` | Flips one CRC bit on every token and data PID (OUT, IN, SETUP, SOF, DATA0, DATA1). Scoreboard must see `crc_err` only. | 6 x 10 = 60 |
| `usb_pid_err_test` | Flips one PID check bit on every PID (all 9). Scoreboard must see `pid_err` only. | 9 x 10 = 90 |
| `usb_stuff_err_test` | Sends a 1 instead of the first stuff bit on tokens and data packets (data forced to 0xFF, token address forced to 0x7F so a run of six 1s exists). Scoreboard must see `stuff_err` only. | 6 x 10 = 60 |
| `usb_mixed_test` | Random packets: 40% good, 20% each of the three errors. | 600 |

Each test prints `TEST PASSED` or `TEST FAILED`. It fails on any UVM error or any SVA failure.

## How to run

CRC check in Python (no simulator needed):

```
python3 sim/check_crc.py
```

QuestaSim (needs `vlib`, `vlog`, `vsim`, `vcover` in PATH):

```
cd sim
./run_questa.sh                    # all 5 tests, seed 1, merged coverage
./run_questa.sh usb_mixed_test 5   # one test with seed 5
```

Vivado xsim (written from the Vivado docs, not tested, may need small changes; xsim does not merge
coverage here, so use the `COVERAGE` line of each test log):

```
cd sim
./run_xsim.sh usb_rand_test
```

Small test without UVM (needs Verilator, or use the Questa line inside the script):

```
cd sim
./run_smoke.sh
./run_mutants.sh     # breaks the RTL on purpose, the smoke test should fail every time
```

`sim/summarize.sh` only prints the key lines (PASS/FAIL, packet counts, coverage, SVA) from the logs.

## Design notes

- Stuffing is counted from the SYNC bits and also applies after the last CRC bit.
- The reference model must be written differently from the RTL. I wrote the CRC in two styles
  (shift left like the RTL, shift right like the reference model). `sim/check_crc.py` compares them
  against known USB data, and `smoke_tb` repeats the known-packet check on the SystemVerilog
  reference model.
- To test an error, the scoreboard must know the exact flag that should come out. So the stuff error
  is an "extra bad stuff bit that the rx drops", and the PID error only flips a check bit. Only one
  flag changes each time.
- An assertion pass action also runs when nothing was checked (empty pass), so `checked` is counted
  separately. Cover properties show that the interesting cases really happen.
- `sim/run_mutants.sh` breaks the RTL on purpose (wrong polynomial, wrong stuffing count, inverted NRZI, ...)
  to prove the smoke test can fail. It works on the smoke test, not on the UVM tests.

## What is not covered

- No real D+/D-, no clock recovery or 48 MHz oversampling, no timing between packets, no EOP width checks.
- The rx does not check the SYNC pattern, it only counts 8 bits.
- No SPLIT, PING, NYET, MDATA, or other PIDs, no Low-Speed or High-Speed.
- A packet with a wrong length is just reported as `crc_err`.
- Only one error type is injected per packet. Two errors at once are not tested.
- Stuffing errors are only injected on tokens and data packets, where I forced a run of six 1s.
- The testbench is back to back (tx -> rx). There is no model of a noisy line.
- The DUT is a behavioural model (tasks and loops), written for simulation, not for synthesis.
