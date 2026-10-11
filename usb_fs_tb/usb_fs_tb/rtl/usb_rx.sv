// usb_rx.sv - takes the serial line stream and rebuilds the packet.
// Steps: undo NRZI -> undo bit stuffing -> collect SYNC, PID, body -> at EOP check PID and CRC.
// It does not check the SYNC pattern, it just counts 8 bits.
module usb_rx
  import usb_pkg::*;
(
  input  logic         clk,
  input  logic         rst_n,
  input  logic         line_valid,
  input  logic         line_j,
  input  logic         line_eop,
  output logic         rx_done,      // 1 clock pulse when a packet is decoded
  output logic [3:0]   rx_pid,
  output logic [7:0]   rx_pid_byte,
  output logic [6:0]   rx_addr,
  output logic [3:0]   rx_endp,
  output logic [6:0]   rx_len,
  output logic [511:0] rx_data,
  output logic         crc_err,
  output logic         stuff_err,
  output logic         pid_err
);

  typedef enum logic [1:0] {R_SYNC, R_PID, R_BODY} rstate_t;
  rstate_t state;

  logic         prev_j;        // line level of the previous bit (for NRZI)
  int           ones;          // 1s in a row seen so far
  logic         expect_stuff;  // next bit should be a stuffed 0
  logic         stuff_bad;     // saw a stuffing mistake in this packet
  int           cnt;           // bit counter for SYNC and PID
  int           nbits;         // body bits collected (fields + CRC)
  logic [7:0]   pid_sh;
  logic [527:0] body;          // up to 512 data bits + 16 CRC bits
  logic         bit_in, got_bit;
  logic         bad_crc, bad_pid;

  task reset_rx;
    state = R_SYNC; cnt = 0; nbits = 0; ones = 0;
    expect_stuff = 0; stuff_bad = 0; prev_j = 1;   // idle line is J
    pid_sh = 0; body = 0;
  endtask

  // called at EOP: check PID + CRC and drive the outputs
  task finish_packet;
    integer k, plen;
    logic [4:0]   c5, r5;
    logic [15:0]  c16, r16;
    logic [511:0] d;
    begin
      rx_pid <= pid_sh[3:0];  rx_pid_byte <= pid_sh;
      rx_addr <= 0; rx_endp <= 0; rx_len <= 0; rx_data <= 0;
      bad_crc = 0;
      bad_pid = (pid_sh[7:4] != ~pid_sh[3:0]);
      if (expect_stuff) stuff_bad = 1;             // EOP came while a stuff bit was owed

      case (pid_sh[3:0])
        PID_OUT, PID_IN, PID_SETUP, PID_SOF: begin // token: 11 field bits + 5 CRC bits
          if (nbits != 16) bad_crc = 1;            // wrong length is reported as crc_err
          else begin
            c5 = 5'h1F;
            for (k = 0; k < 11; k = k + 1) c5 = crc5_step(c5, body[k]);
            r5 = {body[11], body[12], body[13], body[14], body[15]};   // first bit = MSB
            bad_crc = (r5 != ~c5);
            rx_addr <= body[6:0];
            rx_endp <= body[10:7];
          end
        end
        PID_DATA0, PID_DATA1: begin                // data: n bytes + 16 CRC bits
          if (nbits < 16 || ((nbits - 16) % 8) != 0 || ((nbits - 16) / 8) > 64) bad_crc = 1;
          else begin
            plen = (nbits - 16) / 8;
            c16 = 16'hFFFF; d = 0;
            for (k = 0; k < plen * 8; k = k + 1) begin
              c16 = crc16_step(c16, body[k]);
              d[k] = body[k];
            end
            r16 = 0;
            for (k = 0; k < 16; k = k + 1) r16 = {r16[14:0], body[plen * 8 + k]};
            bad_crc = (r16 != ~c16);
            rx_len  <= plen;
            rx_data <= d;
          end
        end
        PID_ACK, PID_NAK, PID_STALL: begin         // handshake: no more bits
          if (nbits != 0) bad_crc = 1;
        end
        default: bad_pid = 1;                      // not a PID we know
      endcase

      crc_err   <= bad_crc;
      stuff_err <= stuff_bad;
      pid_err   <= bad_pid;
      rx_done   <= 1;
    end
  endtask

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rx_done <= 0; rx_pid <= 0; rx_pid_byte <= 0; rx_addr <= 0; rx_endp <= 0;
      rx_len <= 0; rx_data <= 0; crc_err <= 0; stuff_err <= 0; pid_err <= 0;
      reset_rx;
    end else begin
      rx_done <= 0;
      if (line_valid) begin
        // undo NRZI: same level as before = 1, level changed = 0
        bit_in = (line_j == prev_j);
        prev_j = line_j;

        // undo bit stuffing: after six 1s the next bit is a stuffed 0 and is dropped
        got_bit = 0;
        if (expect_stuff) begin
          if (bit_in) stuff_bad = 1;               // it was a 1, so stuffing error
          expect_stuff = 0;
          ones = 0;
        end else begin
          got_bit = 1;
          if (bit_in) ones = ones + 1; else ones = 0;
          if (ones == 6) expect_stuff = 1;
        end

        if (got_bit) begin
          case (state)
            R_SYNC: begin
              cnt = cnt + 1;
              if (cnt == 8) begin state = R_PID; cnt = 0; end
            end
            R_PID: begin
              pid_sh[cnt] = bit_in;                // LSB first
              cnt = cnt + 1;
              if (cnt == 8) begin state = R_BODY; nbits = 0; end
            end
            R_BODY: begin
              if (nbits < 528) body[nbits] = bit_in;
              nbits = nbits + 1;
            end
          endcase
        end
      end else if (line_eop && !(state == R_SYNC && cnt == 0)) begin
        finish_packet;                              // first EOP clock: report the packet
        reset_rx;                                   // second EOP clock is then ignored
      end
    end
  end

endmodule
