// smoke_tb.sv - quick test without UVM.
// 1) checks the reference model against known real USB packets
// 2) sends random packets (with and without injected errors) through tx -> rx
//    and compares line bits + decoded result with the reference functions
`timescale 1ns/1ps
module smoke_tb;
  import usb_pkg::*;
  import usb_ref_pkg::*;

  logic clk = 0;
  always #5 clk = ~clk;

  logic         rst_n = 0, start = 0;
  logic [3:0]   pid = 0;
  logic [6:0]   addr = 0, len = 0;
  logic [3:0]   endp = 0, inj_bit = 0;
  logic [511:0] data = 0;
  logic         inj_crc = 0, inj_pid = 0, inj_stuff = 0;
  logic         busy, line_valid, line_j, line_eop, stuffed_bit;
  logic [7:0]   tx_pid_byte, rx_pid_byte;
  logic         rx_done, crc_err, stuff_err, pid_err;
  logic [3:0]   rx_pid, rx_endp;
  logic [6:0]   rx_addr, rx_len;
  logic [511:0] rx_data;

  usb_top dut (.*);

  int pass_cnt = 0, fail_cnt = 0;

  // bit queue -> bytes (first bit = bit 0)
  function automatic byte_q_t to_bytes(bit_q_t q);
    byte_q_t r;
    for (int i = 0; i + 7 < q.size(); i += 8) begin
      bit [7:0] b;
      for (int j = 0; j < 8; j++) b[j] = q[i + j];
      r.push_back(b);
    end
    return r;
  endfunction

  // known USB packets: SETUP 0/0 = 2D 00 10, GET_DESCRIPTOR data = ... DD 94
  task check_known_vectors;
    byte_q_t d, got;
    d = {};
    got = to_bytes(ref_packet_bits(PID_SETUP, 7'd0, 4'd0, d, ERR_NONE, 0));
    if (got[1] == 8'h2D && got[2] == 8'h00 && got[3] == 8'h10) pass_cnt++;
    else begin fail_cnt++; $display("FAIL known SETUP token: %p", got); end

    d = {8'h80, 8'h06, 8'h00, 8'h01, 8'h00, 8'h00, 8'h40, 8'h00};
    got = to_bytes(ref_packet_bits(PID_DATA0, 0, 0, d, ERR_NONE, 0));
    if (got[1] == 8'hC3 && got[10] == 8'hDD && got[11] == 8'h94) pass_cnt++;
    else begin fail_cnt++; $display("FAIL known DATA0 packet: %p", got); end

    d = {};
    got = to_bytes(ref_packet_bits(PID_DATA0, 0, 0, d, ERR_NONE, 0));
    if (got[1] == 8'hC3 && got[2] == 8'h00 && got[3] == 8'h00) pass_cnt++;
    else begin fail_cnt++; $display("FAIL known empty DATA0: %p", got); end
  endtask

  task send_and_check(bit [3:0] p, bit [6:0] a, bit [3:0] e, byte_q_t d, usb_err_e err, bit [3:0] ebit);
    bit_q_t exp_line, seen_line;
    bit     injected, ok;
    bit_q_t exp_bits, stuffed;
    int     timeout;

    @(posedge clk); #1;
    pid = p; addr = a; endp = e; len = d.size(); data = '0;
    foreach (d[i]) data[8*i +: 8] = d[i];
    inj_crc = (err == ERR_CRC); inj_pid = (err == ERR_PID); inj_stuff = (err == ERR_STUFF);
    inj_bit = ebit;
    start = 1;
    @(posedge clk); #1; start = 0;

    seen_line = {};
    timeout = 0;
    while (!rx_done && timeout < 2000) begin
      @(posedge clk);
      if (line_valid) seen_line.push_back(line_j);
      timeout++;
    end
    exp_bits = ref_packet_bits(p, a, e, d, err, ebit);
    stuffed  = ref_stuff(exp_bits, err == ERR_STUFF, injected);
    exp_line = ref_nrzi(stuffed);

    ok = (timeout < 2000) && (seen_line == exp_line);
    ok &= (crc_err   == (err == ERR_CRC));
    ok &= (pid_err   == (err == ERR_PID));
    ok &= (stuff_err == injected);
    ok &= (rx_pid == p) && (rx_len == d.size());
    if (pid_kind(p) == K_TOKEN) ok &= (rx_addr == a) && (rx_endp == e);
    foreach (d[i]) ok &= (rx_data[8*i +: 8] == d[i]);

    if (ok) pass_cnt++;
    else begin
      fail_cnt++;
      $display("FAIL pid=%h len=%0d err=%s crc=%b pid_e=%b stuff=%b (line match=%b)",
               p, d.size(), err.name(), crc_err, pid_err, stuff_err, seen_line == exp_line);
    end
    repeat (4) @(posedge clk);
  endtask

  usb_pid_e pids[$] = '{PID_OUT, PID_IN, PID_SOF, PID_SETUP, PID_DATA0, PID_DATA1,
                        PID_ACK, PID_NAK, PID_STALL};
  initial begin
    check_known_vectors;
    repeat (5) @(posedge clk);
    rst_n = 1;
    repeat (3) @(posedge clk);

    for (int n = 0; n < 600; n++) begin
      usb_pid_e  p   = pids[$urandom_range(0, 8)];
      usb_err_e  err = usb_err_e'($urandom_range(0, 3));
      byte_q_t   d   = {};
      bit [6:0]  a   = 0;
      bit [3:0]  e   = 0, ebit = 0;
      usb_kind_e k   = pid_kind(p);

      if (k == K_TOKEN) begin a = $urandom; e = $urandom; end
      if (k == K_DATA)  begin
        int l = $urandom_range(0, 64);
        for (int i = 0; i < l; i++) d.push_back($urandom);
      end
      if (err == ERR_CRC && k == K_HS) err = ERR_NONE;
      if (err == ERR_CRC) ebit = $urandom_range(0, (k == K_TOKEN) ? 4 : 15);
      if (err == ERR_PID) ebit = $urandom_range(0, 3);
      if (err == ERR_STUFF) begin                           // a run of 1s is needed
        if (k == K_HS) err = ERR_NONE;
        else if (k == K_TOKEN) a = 7'h7F;
        else begin d = {8'hFF, 8'hFF}; end
      end
      send_and_check(p, a, e, d, err, ebit);
    end

    $display("SMOKE RESULT: pass=%0d fail=%0d", pass_cnt, fail_cnt);
    if (fail_cnt == 0) $display("SMOKE PASSED"); else $display("SMOKE FAILED");
    $finish;
  end
endmodule
