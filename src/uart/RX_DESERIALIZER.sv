//-----------------------------------------------------------------------------
// Title         : rx_deserializer
// Project       : riscv-dbg-uart
//-----------------------------------------------------------------------------
// File          : rx_deserializer.sv
// Author        : Stephan Proß  <spross@S-PC>
// Created       : 29.09.2023
// Last modified : 29.09.2023
//-----------------------------------------------------------------------------
// Description :
// 8-Bit deserializer for use in conjunction with the RX-interface and dmi_uart_tap
// module.
//------------------------------------------------------------------------------
// Modification history :
// 29.09.2023 : created
//-----------------------------------------------------------------------------

import uart_pkg::*;

module RX_DESERIALIZER #(
    parameter integer unsigned MAX_BITS
) (  /*AUTOARG*/
    // Outputs
    BUSY_O,
    DONE_O,
    DATA_O,
    // Inputs
    CLK_I,
    RST_I,
    LENGTH_I,
    DATA_BYTE_I,
    RUN_I
);

  // Ingoing signals
  input logic CLK_I;
  input logic RST_I;
  input [$clog2(MAX_BITS)-1:0] LENGTH_I;
  input logic [7:0] DATA_BYTE_I;
  input logic RUN_I;

  // Outgoing signals
  output logic BUSY_O;
  output logic DONE_O;
  output logic [MAX_BITS-1:0] DATA_O;

  bit [$clog2(MAX_BITS)-1:0] length;
  assign length = LENGTH_I;

  bit [$clog2(MAX_BITS)-1:0] byte_count;
  always_ff @(posedge CLK_I) begin : DE_SERIALIZE
    if (RST_I) begin
      byte_count <= 0;
      DONE_O <= 0;
      BUSY_O <= 0;
      DATA_O <= '0;
    end else begin
      if (byte_count < length) begin
        DONE_O <= 0;
        if (RUN_I) begin
          BUSY_O <= 1;
          DATA_O[byte_count+:8] <= DATA_BYTE_I;
          byte_count <= byte_count + 8;
        end
      end else if (BUSY_O) begin
        DONE_O <= 1;
      end
    end  // else: !if(!RST_NI || RST_I)
  end  // block: DE_SERIALIZE

endmodule  // RX_DESERIALIZER
// Local Variables:
// verilog-library-flags:("-f ../../include.vc")
// End:
