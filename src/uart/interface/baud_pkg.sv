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
    assert (hz > ovsamp_rate * baudrate)
      else
        $error("Baudrate must be smaller than Clock Rate / ovsamp_rate!");
    if (hz > ovsamp_rate*baudrate) begin
      return (hz/ovsamp_rate*baudrate);
    end
    return 1;
  endfunction // integer

  function automatic integer ovsamp( integer hz );
    return ovsamp_rate;
  endfunction // integer

endpackage : baud_pkg
