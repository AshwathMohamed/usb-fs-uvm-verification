// usb_tests.sv - the five tests

// base test: builds the env, runs run_seqs(), prints PASS/FAIL.
// A test fails if there is any UVM error or any SVA failure.
class usb_base_test extends uvm_test;
  `uvm_component_utils(usb_base_test)

  usb_env        env;
  virtual usb_if vif;

  function new(string name = "usb_base_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = usb_env::type_id::create("env", this);
    if (!uvm_config_db#(virtual usb_if)::get(this, "", "vif", vif))
      `uvm_fatal("TEST", "no virtual interface")
  endfunction

  virtual task run_seqs();           // each test fills this in
  endtask

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    run_seqs();
    #2us;                            // let the last packet drain
    phase.drop_objection(this);
  endtask

  function void report_phase(uvm_phase phase);
    uvm_report_server svr = uvm_report_server::get_server();
    int sva_fails = vif.tx_pid_fail + vif.rx_pid_fail + vif.ones_fail;
    if (svr.get_severity_count(UVM_ERROR) + svr.get_severity_count(UVM_FATAL) == 0 && sva_fails == 0)
      `uvm_info("TEST", $sformatf("TEST PASSED: %s", get_type_name()), UVM_NONE)
    else
      `uvm_info("TEST", $sformatf("TEST FAILED: %s", get_type_name()), UVM_NONE)
  endfunction
endclass

// 1) random valid packets only
class usb_rand_test extends usb_base_test;
  `uvm_component_utils(usb_rand_test)
  function new(string name = "usb_rand_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  task run_seqs();
    usb_valid_seq seq = usb_valid_seq::type_id::create("seq");
    seq.n = 300;
    seq.start(env.agent.sqr);
  endtask
endclass

// 2) CRC error on every packet type that has a CRC
class usb_crc_err_test extends usb_base_test;
  `uvm_component_utils(usb_crc_err_test)
  function new(string name = "usb_crc_err_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  task run_seqs();
    usb_err_seq seq = usb_err_seq::type_id::create("seq");
    seq.err = ERR_CRC;
    seq.start(env.agent.sqr);
  endtask
endclass

// 3) PID check-bit error on every packet type
class usb_pid_err_test extends usb_base_test;
  `uvm_component_utils(usb_pid_err_test)
  function new(string name = "usb_pid_err_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  task run_seqs();
    usb_err_seq seq = usb_err_seq::type_id::create("seq");
    seq.err = ERR_PID;
    seq.start(env.agent.sqr);
  endtask
endclass

// 4) stuffing violation on tokens and data packets
class usb_stuff_err_test extends usb_base_test;
  `uvm_component_utils(usb_stuff_err_test)
  function new(string name = "usb_stuff_err_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  task run_seqs();
    usb_err_seq seq = usb_err_seq::type_id::create("seq");
    seq.err = ERR_STUFF;
    seq.start(env.agent.sqr);
  endtask
endclass

// 5) random mix of good packets and all three error types
class usb_mixed_test extends usb_base_test;
  `uvm_component_utils(usb_mixed_test)
  function new(string name = "usb_mixed_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  task run_seqs();
    usb_mixed_seq seq = usb_mixed_seq::type_id::create("seq");
    seq.n = 600;
    seq.start(env.agent.sqr);
  endtask
endclass
