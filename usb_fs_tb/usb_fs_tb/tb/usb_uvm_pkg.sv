// usb_uvm_pkg.sv - all UVM classes in one package
package usb_uvm_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import usb_pkg::*;
  import usb_ref_pkg::*;

  `include "usb_item.sv"
  `include "usb_sequences.sv"
  `include "usb_driver.sv"
  `include "usb_monitor.sv"
  `include "usb_agent.sv"
  `include "usb_scoreboard.sv"
  `include "usb_coverage.sv"
  `include "usb_env.sv"
endpackage
