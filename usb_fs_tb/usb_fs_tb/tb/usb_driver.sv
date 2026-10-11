// usb_driver.sv - takes items from the sequencer and drives them into the DUT
class usb_driver extends uvm_driver #(usb_item);
  `uvm_component_utils(usb_driver)

  virtual usb_if vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual usb_if)::get(this, "", "vif", vif))
      `uvm_fatal("DRV", "no virtual interface")
  endfunction

  task run_phase(uvm_phase phase);
    wait (vif.rst_n === 1'b1);
    repeat (3) @(posedge vif.clk);
    forever begin
      seq_item_port.get_next_item(req);
      drive_item(req);
      seq_item_port.item_done();
    end
  endtask

  task drive_item(usb_item t);
    logic [511:0] d = '0;
    int unsigned  guard = 0;

    foreach (t.data[i]) d[8*i +: 8] = t.data[i];

    // put the packet on the inputs and pulse start for one clock
    @(posedge vif.clk);
    vif.pid       <= t.pid;
    vif.addr      <= t.addr;
    vif.endp      <= t.endp;
    vif.len       <= t.data.size();
    vif.data      <= d;
    vif.inj_crc   <= (t.err_type == ERR_CRC);
    vif.inj_pid   <= (t.err_type == ERR_PID);
    vif.inj_stuff <= (t.err_type == ERR_STUFF);
    vif.inj_bit   <= t.err_bit;
    vif.start     <= 1;
    @(posedge vif.clk);
    vif.start     <= 0;

    // wait until tx is finished (busy goes high, then low again)
    repeat (2) @(posedge vif.clk);
    while (vif.busy && guard < 5000) begin
      @(posedge vif.clk);
      guard++;
    end
    if (guard >= 5000) `uvm_error("DRV", "tx never finished (busy stuck high)")

    repeat (4) @(posedge vif.clk);   // small gap between packets
  endtask
endclass
