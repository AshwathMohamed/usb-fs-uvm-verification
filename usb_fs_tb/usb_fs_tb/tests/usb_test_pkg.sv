// usb_test_pkg.sv - package that holds the tests
package usb_test_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import usb_pkg::*;
  import usb_ref_pkg::*;
  import usb_uvm_pkg::*;

  `include "usb_tests.sv"
endpackage
