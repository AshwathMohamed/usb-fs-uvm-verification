// usb_env.sv - agent + scoreboard + coverage
class usb_env extends uvm_env;
  `uvm_component_utils(usb_env)

  usb_agent      agent;
  usb_scoreboard scb;
  usb_coverage   cov;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    agent = usb_agent::type_id::create("agent", this);
    scb   = usb_scoreboard::type_id::create("scb", this);
    cov   = usb_coverage::type_id::create("cov", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    agent.mon.ap_in.connect(scb.in_fifo.analysis_export);
    agent.mon.ap_out.connect(scb.out_fifo.analysis_export);
    agent.mon.ap_in.connect(cov.analysis_export);
  endfunction
endclass
