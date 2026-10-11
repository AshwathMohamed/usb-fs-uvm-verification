// usb_ref_pkg.sv - reference model as plain functions (no UVM in here).
// The scoreboard calls these to work out what the DUT should do.
// The CRC is written the "reflected" way (shift right, 0x14 / 0xA001) so it is a different
// style from the DUT (shift left) and not just a copy of it.
package usb_ref_pkg;
  import usb_pkg::*;

  typedef bit       bit_q_t[$];
  typedef bit [7:0] byte_q_t[$];

  typedef enum {K_TOKEN, K_DATA, K_HS}                 usb_kind_e;
  typedef enum {ERR_NONE, ERR_CRC, ERR_PID, ERR_STUFF} usb_err_e;

  function automatic usb_kind_e pid_kind(bit [3:0] pid);
    case (pid[1:0])
      2'b01:   return K_TOKEN;
      2'b11:   return K_DATA;
      default: return K_HS;
    endcase
  endfunction

  // add a byte to a bit queue, LSB first
  function automatic void push_byte(ref bit_q_t q, input bit [7:0] b);
    for (int i = 0; i < 8; i++) q.push_back(b[i]);
  endfunction

  // CRC5, init all ones. Returns the register (not inverted yet).
  function automatic bit [4:0] ref_crc5(bit_q_t d);
    bit [4:0] r = 5'h1F;
    foreach (d[i]) begin
      if (r[0] ^ d[i]) r = (r >> 1) ^ 5'h14;     // 0x14 = 0x05 bit-reversed
      else             r = (r >> 1);
    end
    return r;
  endfunction

  // CRC16, init all ones. Returns the register (not inverted yet).
  function automatic bit [15:0] ref_crc16(bit_q_t d);
    bit [15:0] r = 16'hFFFF;
    foreach (d[i]) begin
      if (r[0] ^ d[i]) r = (r >> 1) ^ 16'hA001;  // 0xA001 = 0x8005 bit-reversed
      else             r = (r >> 1);
    end
    return r;
  endfunction

  // SYNC + PID + fields + CRC before stuffing, with the error injected if asked.
  // err_bit: CRC -> which CRC bit on the wire (0 = first), PID -> which check bit (0 to 3)
  function automatic bit_q_t ref_packet_bits(bit [3:0] pid, bit [6:0] addr, bit [3:0] endp,
                                             byte_q_t data, usb_err_e err, bit [3:0] err_bit);
    bit_q_t    q, body;
    bit [7:0]  pid_byte;
    bit [4:0]  crc5;
    bit [15:0] crc16;

    q = {}; body = {};
    push_byte(q, 8'h80);                                   // SYNC
    pid_byte = {~pid, pid};
    if (err == ERR_PID) pid_byte[4 + err_bit[1:0]] = ~pid_byte[4 + err_bit[1:0]];
    push_byte(q, pid_byte);

    case (pid_kind(pid))
      K_TOKEN: begin
        for (int i = 0; i < 7; i++) body.push_back(addr[i]);
        for (int i = 0; i < 4; i++) body.push_back(endp[i]);
        crc5 = ~ref_crc5(body);                            // in this style bit 0 goes first
        if (err == ERR_CRC) crc5[err_bit] = ~crc5[err_bit];
        foreach (body[i]) q.push_back(body[i]);
        for (int i = 0; i < 5; i++) q.push_back(crc5[i]);
      end
      K_DATA: begin
        foreach (data[j]) for (int i = 0; i < 8; i++) body.push_back(data[j][i]);
        crc16 = ~ref_crc16(body);
        if (err == ERR_CRC) crc16[err_bit] = ~crc16[err_bit];
        foreach (body[i]) q.push_back(body[i]);
        for (int i = 0; i < 16; i++) q.push_back(crc16[i]);
      end
      default: ;                                           // handshake: nothing more
    endcase
    return q;
  endfunction

  // Bit stuffing: after six 1s insert a 0. If bad is set, the first stuff bit is a 1
  // instead (stuffing violation). 'injected' tells if that really happened.
  function automatic bit_q_t ref_stuff(bit_q_t in, bit bad, output bit injected);
    bit_q_t out;
    int     ones = 0;
    out = {};
    injected = 0;
    for (int i = 0; i <= in.size(); i++) begin
      if (ones == 6) begin                                 // a stuff bit is also needed after the last bit
        if (bad && !injected) begin out.push_back(1); injected = 1; end
        else                  out.push_back(0);
        ones = 0;
      end
      if (i < in.size()) begin
        out.push_back(in[i]);
        ones = in[i] ? ones + 1 : 0;
      end
    end
    return out;
  endfunction

  // NRZI: a 0 toggles the line, a 1 keeps it. Line starts at J (1). Returns the level per bit.
  function automatic bit_q_t ref_nrzi(bit_q_t in);
    bit_q_t out;
    bit level = 1;
    out = {};
    foreach (in[i]) begin
      if (!in[i]) level = ~level;
      out.push_back(level);
    end
    return out;
  endfunction

endpackage
