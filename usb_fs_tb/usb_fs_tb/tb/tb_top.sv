// tb_top.sv - clock, reset, DUT, interface, and start of UVM
`timescale 1ns/1ps
module tb_top;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import usb_test_pkg::*;

  logic clk = 0;
  always #41.667 clk = ~clk;          // about 12 MHz: one clock = one bit (Full-Speed rate)

  usb_if vif (clk);

  usb_top dut (
    .clk(clk), .rst_n(vif.rst_n),
    .start(vif.start), .pid(vif.pid), .addr(vif.addr), .endp(vif.endp),
    .len(vif.len), .data(vif.data),
    .inj_crc(vif.inj_crc), .inj_pid(vif.inj_pid), .inj_stuff(vif.inj_stuff), .inj_bit(vif.inj_bit),
    .busy(vif.busy),
    .line_valid(vif.line_valid), .line_j(vif.line_j), .line_eop(vif.line_eop),
    .stuffed_bit(vif.stuffed_bit), .tx_pid_byte(vif.tx_pid_byte),
    .rx_done(vif.rx_done), .rx_pid(vif.rx_pid), .rx_pid_byte(vif.rx_pid_byte),
    .rx_addr(vif.rx_addr), .rx_endp(vif.rx_endp), .rx_len(vif.rx_len), .rx_data(vif.rx_data),
    .crc_err(vif.crc_err), .stuff_err(vif.stuff_err), .pid_err(vif.pid_err)
  );

  initial begin
    vif.rst_n = 0;
    repeat (5) @(posedge clk);
    vif.rst_n = 1;
  end

  initial begin
    uvm_config_db#(virtual usb_if)::set(null, "*", "vif", vif);
    run_test();                       // test name comes from +UVM_TESTNAME
  end

  final begin
    $display("SVA_SUMMARY tx_pid_check checked=%0d fail=%0d | rx_pid_check checked=%0d fail=%0d | max_six_ones bits_checked=%0d fail=%0d",
             vif.tx_pid_checked, vif.tx_pid_fail, vif.rx_pid_checked, vif.rx_pid_fail,
             vif.ones_checked, vif.ones_fail);
  end
endmodule
