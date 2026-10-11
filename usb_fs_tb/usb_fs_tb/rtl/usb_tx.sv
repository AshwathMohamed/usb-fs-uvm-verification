// usb_tx.sv - turns a packet into a serial line stream.
// One clock = one bit time. Line: line_j = 1 is J, 0 is K, line_eop = 1 is end of packet.
// Order: SYNC, PID, fields, CRC -> bit stuffing -> NRZI -> EOP
module usb_tx
  import usb_pkg::*;
(
  input  logic         clk,
  input  logic         rst_n,
  input  logic         start,        // 1 clock pulse: take the packet below
  input  logic [3:0]   pid,
  input  logic [6:0]   addr,         // for SOF the 11-bit frame number is {endp, addr}
  input  logic [3:0]   endp,
  input  logic [6:0]   len,          // data bytes (0 to 64)
  input  logic [511:0] data,         // byte i = data[8*i +: 8]
  // error injection, use one at a time
  input  logic         inj_crc,      // flip one CRC bit
  input  logic         inj_pid,      // flip one PID check bit
  input  logic         inj_stuff,    // send a 1 instead of the first stuff bit
  input  logic [3:0]   inj_bit,      // CRC: which bit on the wire (0 = first). PID: which check bit (0 to 3)
  output logic         busy,
  output logic         line_valid,   // a bit is on the line this clock
  output logic         line_j,
  output logic         line_eop,
  output logic         stuffed_bit,  // bit after stuffing, before NRZI (used by SVA)
  output logic [7:0]   pid_byte_o    // PID byte really sent (used by SVA)
);

  typedef enum logic [1:0] {S_IDLE, S_SEND, S_EOP1, S_EOP2} state_t;
  state_t state;

  logic [543:0] bits;       // SYNC + PID + fields + CRC before stuffing (max 544 bits)
  int           nbits;
  int           idx;        // next bit to send
  int           ones;       // 1s in a row on the stuffed stream
  logic         inj_stuff_r, inj_done;
  logic         out_bit;
  logic [4:0]   c5;
  logic [15:0]  c16;
  logic [7:0]   pid_byte_v;

  task push_bit(input logic b);
    bits[nbits] = b;
    nbits = nbits + 1;
  endtask

  task push_byte(input logic [7:0] v);   // LSB first
    integer k;
    for (k = 0; k < 8; k = k + 1) push_bit(v[k]);
  endtask

  // field bits go on the line and into both CRC engines
  task push_field_bit(input logic b);
    push_bit(b);
    c5  = crc5_step(c5, b);
    c16 = crc16_step(c16, b);
  endtask

  task build_packet;
    integer k;
    logic [4:0]  v5;
    logic [15:0] v16;
    begin
      bits = '0; nbits = 0;
      c5 = 5'h1F; c16 = 16'hFFFF;
      push_byte(8'h80);                          // SYNC: seven 0s then a 1 (KJKJKJKK)
      pid_byte_v = {~pid, pid};
      if (inj_pid) pid_byte_v[4 + inj_bit[1:0]] = ~pid_byte_v[4 + inj_bit[1:0]];
      push_byte(pid_byte_v);
      case (pid[1:0])
        2'b01: begin                             // token: addr(7) endp(4) crc5
          for (k = 0; k < 7; k = k + 1) push_field_bit(addr[k]);
          for (k = 0; k < 4; k = k + 1) push_field_bit(endp[k]);
          v5 = ~c5;                              // CRC output is inverted
          if (inj_crc) v5[4 - inj_bit] = ~v5[4 - inj_bit];
          for (k = 4; k >= 0; k = k - 1) push_bit(v5[k]);    // CRC is sent MSB first
        end
        2'b11: begin                             // data: bytes then crc16
          for (k = 0; k < len * 8; k = k + 1) push_field_bit(data[k]);
          v16 = ~c16;
          if (inj_crc) v16[15 - inj_bit] = ~v16[15 - inj_bit];
          for (k = 15; k >= 0; k = k - 1) push_bit(v16[k]);
        end
        default: ;                               // handshake: PID only
      endcase
    end
  endtask

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= S_IDLE; busy <= 0;
      line_valid <= 0; line_j <= 1; line_eop <= 0; stuffed_bit <= 0;
      pid_byte_o <= 0;
    end else begin
      case (state)
        S_IDLE: begin
          line_valid <= 0; line_eop <= 0; line_j <= 1;   // idle line = J
          busy <= 0;
          if (start) begin
            build_packet;
            pid_byte_o  <= pid_byte_v;
            inj_stuff_r  = inj_stuff;
            inj_done     = 0;
            idx = 0; ones = 0;
            busy  <= 1;
            state <= S_SEND;
          end
        end

        S_SEND: begin
          if (ones != 6 && idx >= nbits) begin      // all sent, and no stuff bit owed
            line_valid <= 0;
            line_eop   <= 1;
            state      <= S_EOP1;
          end else begin
            if (ones == 6) begin                    // six 1s in a row -> stuff a 0
              out_bit = 0;
              if (inj_stuff_r && !inj_done) begin   // error injection: send a 1 instead
                out_bit  = 1;
                inj_done = 1;
              end
              ones = 0;
            end else begin
              out_bit = bits[idx];
              idx = idx + 1;
              if (out_bit) ones = ones + 1; else ones = 0;
            end
            line_valid  <= 1;
            stuffed_bit <= out_bit;
            if (!out_bit) line_j <= ~line_j;        // NRZI: 0 = toggle, 1 = stay
          end
        end

        S_EOP1: begin                               // EOP lasts two clocks
          line_eop <= 1;
          state    <= S_EOP2;
        end

        S_EOP2: begin
          line_eop <= 0;
          busy     <= 0;
          state    <= S_IDLE;
        end
      endcase
    end
  end

endmodule
