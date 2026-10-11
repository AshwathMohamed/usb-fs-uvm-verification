// usb_item.sv - one USB packet (what we send) plus what came out (filled by the monitor)
class usb_item extends uvm_sequence_item;
  `uvm_object_utils(usb_item)

  rand usb_kind_e kind;
  rand usb_pid_e  pid;
  rand bit [6:0]  addr;          // tokens only (for SOF the frame number is {endp, addr})
  rand bit [3:0]  endp;          // tokens only
  rand byte_q_t   data;          // data packets only, 0 to 64 bytes
  rand usb_err_e  err_type;      // ERR_NONE = good packet
  rand bit [3:0]  err_bit;       // CRC: which CRC bit on the wire. PID: which check bit (0 to 3)

  // filled in by the monitor on the output side
  bit crc_err, stuff_err, pid_err;
  bit line[$];                   // J/K level of every bit seen on the line (1 = J)

  constraint kind_c {
    (kind == K_TOKEN) -> pid inside {PID_OUT, PID_IN, PID_SETUP, PID_SOF};
    (kind == K_DATA)  -> pid inside {PID_DATA0, PID_DATA1};
    (kind == K_HS)    -> pid inside {PID_ACK, PID_NAK, PID_STALL};
  }

  // unused fields stay 0 so the scoreboard can compare everything directly
  constraint fields_c {
    (kind != K_TOKEN) -> (addr == 0 && endp == 0);
    (kind != K_DATA)  -> data.size() == 0;
    if (kind == K_DATA) {
      data.size() dist {0 := 10, [1:8] :/ 30, [9:32] :/ 30, [33:63] :/ 20, 64 := 10};
    }
  }

  constraint err_c {
    (kind == K_HS) -> err_type inside {ERR_NONE, ERR_PID};   // handshake has no CRC and no run of 1s
    if (err_type == ERR_CRC) err_bit < ((kind == K_TOKEN) ? 5 : 16);
    if (err_type == ERR_PID) err_bit < 4;
    // a stuffing error needs a run of six 1s, so force one
    if (err_type == ERR_STUFF) {
      (kind == K_TOKEN) -> (addr == 7'h7F);
      if (kind == K_DATA) {
        data.size() >= 1;
        foreach (data[i]) data[i] == 8'hFF;
      }
    }
  }

  // default is a good packet, sequences override this
  constraint err_default_c { soft err_type == ERR_NONE; }

  function new(string name = "usb_item");
    super.new(name);
  endfunction

  function string convert2string();
    return $sformatf("pid=%s addr=%0h endp=%0h len=%0d err=%s err_bit=%0d | crc_err=%b stuff_err=%b pid_err=%b",
                     pid.name(), addr, endp, data.size(), err_type.name(), err_bit,
                     crc_err, stuff_err, pid_err);
  endfunction
endclass
