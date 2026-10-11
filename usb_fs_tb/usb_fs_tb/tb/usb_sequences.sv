// usb_sequences.sv - stimulus sequences

// good packets only
class usb_valid_seq extends uvm_sequence #(usb_item);
  `uvm_object_utils(usb_valid_seq)
  int unsigned n = 200;

  function new(string name = "usb_valid_seq");
    super.new(name);
  endfunction

  task body();
    repeat (n) begin
      req = usb_item::type_id::create("req");
      start_item(req);
      if (!req.randomize() with { err_type == ERR_NONE; })
        `uvm_fatal("SEQ", "randomize failed")
      finish_item(req);
    end
  endtask
endclass

// one error type, walks through every packet type that can have it
class usb_err_seq extends uvm_sequence #(usb_item);
  `uvm_object_utils(usb_err_seq)
  usb_err_e err      = ERR_CRC;               // set by the test
  int unsigned reps  = 10;                    // packets per PID

  function new(string name = "usb_err_seq");
    super.new(name);
  endfunction

  task body();
    usb_pid_e all_pids[$] = '{PID_OUT, PID_IN, PID_SETUP, PID_SOF, PID_DATA0, PID_DATA1,
                              PID_ACK, PID_NAK, PID_STALL};
    foreach (all_pids[i]) begin
      usb_pid_e p = all_pids[i];
      // handshakes have no CRC and cannot have a stuffing error
      if (pid_kind(p) == K_HS && err != ERR_PID) continue;
      repeat (reps) begin
        req = usb_item::type_id::create("req");
        start_item(req);
        if (!req.randomize() with { pid == local::p; err_type == local::err; })
          `uvm_fatal("SEQ", "randomize failed")
        finish_item(req);
      end
    end
  endtask
endclass

// random mix of good packets and all error types
class usb_mixed_seq extends uvm_sequence #(usb_item);
  `uvm_object_utils(usb_mixed_seq)
  int unsigned n = 400;

  function new(string name = "usb_mixed_seq");
    super.new(name);
  endfunction

  task body();
    repeat (n) begin
      req = usb_item::type_id::create("req");
      start_item(req);
      if (!req.randomize() with { err_type dist {ERR_NONE := 40, ERR_CRC := 20,
                                                 ERR_PID := 20, ERR_STUFF := 20}; })
        `uvm_fatal("SEQ", "randomize failed")
      finish_item(req);
    end
  endtask
endclass
