// usb_if.sv - signals between the testbench and the DUT, plus the SVA checks
interface usb_if (input logic clk);

  logic         rst_n;

  // driven by the driver
  logic         start     = 0;
  logic [3:0]   pid       = 0;
  logic [6:0]   addr      = 0;
  logic [3:0]   endp      = 0;
  logic [6:0]   len       = 0;
  logic [511:0] data      = 0;
  logic         inj_crc   = 0;
  logic         inj_pid   = 0;
  logic         inj_stuff = 0;
  logic [3:0]   inj_bit   = 0;

  // watched by the monitor
  logic         busy;
  logic         line_valid, line_j, line_eop, stuffed_bit;
  logic [7:0]   tx_pid_byte;
  logic         rx_done;
  logic [3:0]   rx_pid;
  logic [7:0]   rx_pid_byte;
  logic [6:0]   rx_addr;
  logic [3:0]   rx_endp;
  logic [6:0]   rx_len;
  logic [511:0] rx_data;
  logic         crc_err, stuff_err, pid_err;

  // ---------------- SVA ----------------
  // checked = how many times the check really had something to look at, fail = failures.
  // (the assert pass action also fires on empty passes, so it is not used for counting)
  int tx_pid_checked = 0, tx_pid_fail = 0;
  int rx_pid_checked = 0, rx_pid_fail = 0;
  int ones_checked   = 0, ones_fail   = 0;

  // 1 while the current packet has a deliberate stuffing error
  logic inj_stuff_active;
  always @(posedge clk) begin
    if (!rst_n) inj_stuff_active <= 0;
    else if (start && !busy) inj_stuff_active <= inj_stuff;
  end

  always @(posedge clk) if (rst_n) begin
    if (start && !busy && !inj_pid)      tx_pid_checked++;
    if (rx_done && !pid_err)             rx_pid_checked++;
    if (line_valid && !inj_stuff_active) ones_checked++;     // counts stream bits
  end

  // 1) PID check bits are the complement of the PID on valid packets.
  //    Valid = no PID error injected. tx_pid_byte is loaded one clock after start.
  a_tx_pid_check: assert property (
    @(posedge clk) disable iff (!rst_n)
    (start && !busy && !inj_pid) |=> (tx_pid_byte[7:4] == ~tx_pid_byte[3:0])
  ) else begin tx_pid_fail++; $error("SVA: tx PID check bits are not the complement"); end

  // same check on the rx side: if rx did not flag pid_err, the check bits must be good
  a_rx_pid_check: assert property (
    @(posedge clk) disable iff (!rst_n)
    (rx_done && !pid_err) |-> (rx_pid_byte[7:4] == ~rx_pid_byte[3:0])
  ) else begin rx_pid_fail++; $error("SVA: rx accepted a PID with bad check bits"); end

  // 2) the stuffed stream never has seven 1s in a row.
  //    Off for the packet where a stuffing error is forced on purpose.
  a_max_six_ones: assert property (
    @(posedge clk) disable iff (!rst_n || inj_stuff_active)
    not ((line_valid && stuffed_bit) [*7])
  ) else begin ones_fail++; $error("SVA: more than six 1s in a row in the stuffed stream"); end

  // cover properties: show the checks above are not passing just because nothing happens
  c_six_ones:     cover property (@(posedge clk) disable iff (!rst_n) (line_valid && stuffed_bit) [*6]);
  c_seven_ones:   cover property (@(posedge clk) disable iff (!rst_n) (line_valid && stuffed_bit) [*7]);   // only in the stuff-error test
  c_bad_pid_sent: cover property (@(posedge clk) disable iff (!rst_n)
                    (start && !busy && inj_pid) |=> (tx_pid_byte[7:4] != ~tx_pid_byte[3:0]));

endinterface
