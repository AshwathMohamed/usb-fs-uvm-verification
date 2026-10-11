// usb_coverage.sv - functional coverage, sampled on every packet given to the DUT
class usb_coverage extends uvm_subscriber #(usb_item);
  `uvm_component_utils(usb_coverage)

  usb_pid_e  c_pid;
  usb_err_e  c_err;
  int        c_len;
  bit        c_is_data;

  covergroup cg;
    option.per_instance = 1;

    cp_type: coverpoint c_pid {
      bins out_p   = {PID_OUT};
      bins in_p    = {PID_IN};
      bins setup_p = {PID_SETUP};
      bins sof_p   = {PID_SOF};
      bins data0_p = {PID_DATA0};
      bins data1_p = {PID_DATA1};
      bins ack_p   = {PID_ACK};
      bins nak_p   = {PID_NAK};
      bins stall_p = {PID_STALL};
    }

    // data packets only
    cp_len: coverpoint c_len iff (c_is_data) {
      bins len_0      = {0};
      bins len_1_8    = {[1:8]};
      bins len_9_32   = {[9:32]};
      bins len_33_63  = {[33:63]};
      bins len_64     = {64};
    }

    cp_err: coverpoint c_err {
      bins no_err     = {ERR_NONE};
      bins crc_error  = {ERR_CRC};
      bins pid_error  = {ERR_PID};
      bins stuff_error= {ERR_STUFF};
    }

    // Handshakes have no CRC and cannot have a run of six 1s, so those 6 combos can never happen.
    x_type_err: cross cp_type, cp_err {
      ignore_bins hs_no_crc_stuff =
        binsof(cp_type) intersect {PID_ACK, PID_NAK, PID_STALL} &&
        binsof(cp_err)  intersect {ERR_CRC, ERR_STUFF};
    }
  endgroup

  function new(string name, uvm_component parent);
    super.new(name, parent);
    cg = new();
  endfunction

  function void write(usb_item t);
    c_pid     = t.pid;
    c_err     = t.err_type;
    c_len     = t.data.size();
    c_is_data = (t.kind == K_DATA);
    cg.sample();
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info("COV", $sformatf("COVERAGE packet_type=%0.2f%% data_len=%0.2f%% error_type=%0.2f%% type_x_error=%0.2f%% total=%0.2f%%",
              cg.cp_type.get_inst_coverage(), cg.cp_len.get_inst_coverage(),
              cg.cp_err.get_inst_coverage(),  cg.x_type_err.get_inst_coverage(),
              cg.get_inst_coverage()), UVM_NONE)
  endfunction
endclass
