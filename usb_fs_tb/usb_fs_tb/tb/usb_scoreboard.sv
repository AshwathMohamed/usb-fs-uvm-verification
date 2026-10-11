// usb_scoreboard.sv - checks the DUT against the reference model (usb_ref_pkg).
// For every packet it gets two items from the monitor:
//   sent : what was given to the DUT                     (in_fifo)
//   got  : what the DUT put on the line and decoded      (out_fifo)
// It works out the expected line bits and error flags from "sent" and compares.
class usb_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(usb_scoreboard)

  uvm_tlm_analysis_fifo #(usb_item) in_fifo;
  uvm_tlm_analysis_fifo #(usb_item) out_fifo;

  int checked = 0, passed = 0, failed = 0;
  bit waiting = 0;                       // 1 while we have a "sent" but no "got" yet

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    in_fifo  = new("in_fifo", this);
    out_fifo = new("out_fifo", this);
  endfunction

  task run_phase(uvm_phase phase);
    usb_item sent, got;
    forever begin
      in_fifo.get(sent);
      waiting = 1;
      out_fifo.get(got);
      waiting = 0;
      check_one(sent, got);
    end
  endtask

  function void check_one(usb_item s, usb_item o);
    bit_q_t exp_bits, stuffed, exp_line;
    bit     injected, exp_crc, exp_pid, exp_stuff;
    bit     ok = 1;
    string  why = "";

    // expected line
    exp_bits = ref_packet_bits(s.pid, s.addr, s.endp, s.data, s.err_type, s.err_bit);
    stuffed  = ref_stuff(exp_bits, (s.err_type == ERR_STUFF), injected);
    exp_line = ref_nrzi(stuffed);

    // expected error flags
    exp_crc   = (s.err_type == ERR_CRC);
    exp_pid   = (s.err_type == ERR_PID);
    exp_stuff = injected;                       // only set if a bad stuff bit was really sent
    if (s.err_type == ERR_STUFF && !injected)
      `uvm_error("SCB", "stuff error asked for, but packet has no run of six 1s (test bug)")

    // line
    if (exp_line.size() != o.line.size()) begin
      ok = 0;
      why = {why, $sformatf(" line_len exp=%0d got=%0d;", exp_line.size(), o.line.size())};
    end else begin
      foreach (exp_line[i])
        if (exp_line[i] !== o.line[i]) begin
          ok = 0;
          why = {why, $sformatf(" line bit %0d differs;", i)};
          break;
        end
    end

    // decoded packet
    if (o.pid  !== s.pid)  begin ok = 0; why = {why, $sformatf(" pid exp=%s got=%s;", s.pid.name(), o.pid.name())}; end
    if (o.addr !== s.addr) begin ok = 0; why = {why, $sformatf(" addr exp=%0h got=%0h;", s.addr, o.addr)}; end
    if (o.endp !== s.endp) begin ok = 0; why = {why, $sformatf(" endp exp=%0h got=%0h;", s.endp, o.endp)}; end
    if (o.data.size() != s.data.size()) begin
      ok = 0;
      why = {why, $sformatf(" len exp=%0d got=%0d;", s.data.size(), o.data.size())};
    end else begin
      foreach (s.data[i])
        if (o.data[i] !== s.data[i]) begin
          ok = 0;
          why = {why, $sformatf(" data[%0d] exp=%0h got=%0h;", i, s.data[i], o.data[i])};
          break;
        end
    end

    // error flags
    if (o.crc_err   !== exp_crc)   begin ok = 0; why = {why, $sformatf(" crc_err exp=%b got=%b;",   exp_crc,   o.crc_err)};   end
    if (o.pid_err   !== exp_pid)   begin ok = 0; why = {why, $sformatf(" pid_err exp=%b got=%b;",   exp_pid,   o.pid_err)};   end
    if (o.stuff_err !== exp_stuff) begin ok = 0; why = {why, $sformatf(" stuff_err exp=%b got=%b;", exp_stuff, o.stuff_err)}; end

    checked++;
    if (ok) begin
      passed++;
      `uvm_info("SCB", $sformatf("PASS %s", s.convert2string()), UVM_HIGH)
    end else begin
      failed++;
      `uvm_error("SCB", $sformatf("FAIL %s |%s", s.convert2string(), why))
    end
  endfunction

  // packets that went in but never came out count as failures
  function void check_phase(uvm_phase phase);
    int lost = in_fifo.used() + (waiting ? 1 : 0);
    if (lost > 0) begin
      failed += lost;
      `uvm_error("SCB", $sformatf("%0d packet(s) sent but DUT never reported them", lost))
    end
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info("SCB", $sformatf("RESULT checked=%0d passed=%0d failed=%0d", checked, passed, failed), UVM_NONE)
  endfunction
endclass
