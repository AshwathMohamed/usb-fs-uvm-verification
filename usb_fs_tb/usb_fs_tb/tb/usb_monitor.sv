// usb_monitor.sv - only watches the pins, never drives them.
//   ap_in  : the packet given to the DUT (seen when start is accepted)
//   ap_out : what came out: line bits + decoded packet + error flags (seen at rx_done)
class usb_monitor extends uvm_monitor;
  `uvm_component_utils(usb_monitor)

  virtual usb_if vif;
  uvm_analysis_port #(usb_item) ap_in;
  uvm_analysis_port #(usb_item) ap_out;

  bit line_q[$];            // line levels of the current packet

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap_in  = new("ap_in", this);
    ap_out = new("ap_out", this);
    if (!uvm_config_db#(virtual usb_if)::get(this, "", "vif", vif))
      `uvm_fatal("MON", "no virtual interface")
  endfunction

  task run_phase(uvm_phase phase);
    forever begin
      @(posedge vif.clk);
      if (vif.rst_n !== 1'b1) continue;

      // the DUT accepts a packet when start is high and tx is not busy
      if (vif.start && !vif.busy) begin
        usb_item t = usb_item::type_id::create("in_item");
        t.pid  = usb_pid_e'(vif.pid);
        t.kind = pid_kind(vif.pid);
        t.addr = vif.addr;
        t.endp = vif.endp;
        for (int i = 0; i < vif.len; i++) t.data.push_back(vif.data[8*i +: 8]);
        if      (vif.inj_crc)   t.err_type = ERR_CRC;
        else if (vif.inj_pid)   t.err_type = ERR_PID;
        else if (vif.inj_stuff) t.err_type = ERR_STUFF;
        else                    t.err_type = ERR_NONE;
        t.err_bit = vif.inj_bit;
        line_q.delete();
        ap_in.write(t);
      end

      if (vif.line_valid) line_q.push_back(vif.line_j);

      if (vif.rx_done) begin
        usb_item o = usb_item::type_id::create("out_item");
        o.pid       = usb_pid_e'(vif.rx_pid);
        o.kind      = pid_kind(vif.rx_pid);
        o.addr      = vif.rx_addr;
        o.endp      = vif.rx_endp;
        for (int i = 0; i < vif.rx_len; i++) o.data.push_back(vif.rx_data[8*i +: 8]);
        o.crc_err   = vif.crc_err;
        o.stuff_err = vif.stuff_err;
        o.pid_err   = vif.pid_err;
        o.line      = line_q;
        line_q.delete();
        ap_out.write(o);
      end
    end
  endtask
endclass
