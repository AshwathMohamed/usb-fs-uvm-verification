// usb_agent.sv - sequencer + driver + monitor

class usb_sequencer extends uvm_sequencer #(usb_item);
  `uvm_component_utils(usb_sequencer)
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
endclass

class usb_agent extends uvm_agent;
  `uvm_component_utils(usb_agent)

  usb_sequencer sqr;
  usb_driver    drv;
  usb_monitor   mon;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    mon = usb_monitor::type_id::create("mon", this);
    if (get_is_active() == UVM_ACTIVE) begin
      sqr = usb_sequencer::type_id::create("sqr", this);
      drv = usb_driver::type_id::create("drv", this);
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    if (get_is_active() == UVM_ACTIVE)
      drv.seq_item_port.connect(sqr.seq_item_export);
  endfunction
endclass
