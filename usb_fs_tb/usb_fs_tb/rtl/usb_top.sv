// usb_top.sv - tx and rx wired back to back, line signals brought out for the testbench
module usb_top (
  input  logic         clk,
  input  logic         rst_n,
  input  logic         start,
  input  logic [3:0]   pid,
  input  logic [6:0]   addr,
  input  logic [3:0]   endp,
  input  logic [6:0]   len,
  input  logic [511:0] data,
  input  logic         inj_crc, inj_pid, inj_stuff,
  input  logic [3:0]   inj_bit,
  output logic         busy,
  output logic         line_valid, line_j, line_eop,
  output logic         stuffed_bit,
  output logic [7:0]   tx_pid_byte,
  output logic         rx_done,
  output logic [3:0]   rx_pid,
  output logic [7:0]   rx_pid_byte,
  output logic [6:0]   rx_addr,
  output logic [3:0]   rx_endp,
  output logic [6:0]   rx_len,
  output logic [511:0] rx_data,
  output logic         crc_err, stuff_err, pid_err
);

  usb_tx u_tx (
    .clk, .rst_n, .start, .pid, .addr, .endp, .len, .data,
    .inj_crc, .inj_pid, .inj_stuff, .inj_bit,
    .busy, .line_valid, .line_j, .line_eop, .stuffed_bit, .pid_byte_o(tx_pid_byte)
  );

  usb_rx u_rx (
    .clk, .rst_n, .line_valid, .line_j, .line_eop,
    .rx_done, .rx_pid, .rx_pid_byte, .rx_addr, .rx_endp, .rx_len, .rx_data,
    .crc_err, .stuff_err, .pid_err
  );

endmodule
