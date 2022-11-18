// -*- Mode: SystemVerilog -*-
// Filename        : baud_pkg.sv
// Description     : Definitions and functions for the uart interface.
// Author          : Stephan Proß
// Created On      : Wed Nov 16 15:04:59 2022
// Last Modified By: Stephan Proß
// Last Modified On: Wed Nov 16 15:04:59 2022
// Update Count    : 0
// Status          : Done.

package baud_pkg;
  localparam integer ovsamp_rate = 8;

  function automatic integer bddiv ( integer hz, integer baudrate );
    return (hz/(ovsamp_rate*baudrate));
  endfunction // bddiv

  function automatic integer ovsamp( integer hz );
    return 8;
  endfunction // ovsamp

endpackage : baud_pkg
