// usb_pkg.sv - PID values and one-bit CRC steps shared by tx and rx
package usb_pkg;

  // low 2 bits of the PID give the group: 01 token, 11 data, 10 handshake
  typedef enum bit [3:0] {
    PID_OUT   = 4'b0001,
    PID_IN    = 4'b1001,
    PID_SOF   = 4'b0101,
    PID_SETUP = 4'b1101,
    PID_DATA0 = 4'b0011,
    PID_DATA1 = 4'b1011,
    PID_ACK   = 4'b0010,
    PID_NAK   = 4'b1010,
    PID_STALL = 4'b1110
  } usb_pid_e;

  // CRC5: x^5 + x^2 + 1 (0x05), shift left
  function automatic logic [4:0] crc5_step(input logic [4:0] c, input logic d);
    logic fb;
    fb = c[4] ^ d;
    crc5_step = {c[3:0], 1'b0};
    if (fb) crc5_step = crc5_step ^ 5'h05;
  endfunction

  // CRC16: x^16 + x^15 + x^2 + 1 (0x8005), shift left
  function automatic logic [15:0] crc16_step(input logic [15:0] c, input logic d);
    logic fb;
    fb = c[15] ^ d;
    crc16_step = {c[14:0], 1'b0};
    if (fb) crc16_step = crc16_step ^ 16'h8005;
  endfunction

endpackage
