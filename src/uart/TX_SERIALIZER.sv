//-----------------------------------------------------------------------------
// Title         : TX_SERIALIZER
// Project       : riscv-dbg-uart
//-----------------------------------------------------------------------------
// File          : tx_serializer.sv
// Author        : Stephan Proß  <spross@S-PC>
// Created       : 29.09.2023
// Last modified : 29.09.2023
//-----------------------------------------------------------------------------
// Description :
// 8-Bit serializer for use in conjunction with the TX-interface and dmi_uart_tap
// module.
//------------------------------------------------------------------------------
// Modification history :
// 29.09.2023 : created
//-----------------------------------------------------------------------------

import uart_pkg::*;

module TX_SERIALIZER #(
    parameter integer unsigned MAX_BITS
) (  /*AUTOARG*/
    // Outputs
    BUSY_O,
    DONE_O,
    DATA_BYTE_O,
    WRITE_O,
    // Inputs
    CLK_I,
    RST_I,
    RUN_I,
    READY_I,
    DATA_I,
    LENGTH_I
);

  // Ingoing signals
  input logic CLK_I;
  input logic RST_I;
  input logic RUN_I;
  input logic READY_I;
  input logic [MAX_BITS-1:0] DATA_I;
  input [$clog2(MAX_BITS)-1:0] LENGTH_I;
  // Outgoing signals
  output logic BUSY_O;
  output logic DONE_O;
  output logic [7:0] DATA_BYTE_O;
  output logic WRITE_O;

  bit [$clog2(MAX_BITS)-1:0] length;
  assign length = LENGTH_I;
  bit [$clog2(MAX_BITS)-1:0] count;

  always_ff @(posedge CLK_I) begin : SERIALIZE
    if (RST_I) begin
      count <= 0;
      BUSY_O <= 0;
      DONE_O <= 0;

      DATA_BYTE_O <= '0;
      WRITE_O <= 0;
    end else begin
      WRITE_O <= 0;
      for (int j = 0; j < 8; j++) begin
        DATA_BYTE_O[j] <= count + j < length ? DATA_I[count+j] : 1'b0;
      end
      // Start serializing if run signal is set.
      // Only possible once after reset.
      if (RUN_I && !DONE_O) begin
        BUSY_O <= 1;
      end
      if (BUSY_O) begin
        // While busy write current word to tx.
        if (count < length) begin
          if (READY_I) begin
            WRITE_O <= 1;
          end
          if (WRITE_O) begin
            // If we have started writing and
            // TX becomes busy, we proceed in
            // the serialization.
            if (!READY_I) begin
              WRITE_O <= 0;
              count   <= count + 8;
            end
          end
        end else begin
          DONE_O <= 1;
          BUSY_O <= 0;
        end
      end
    end
  end

endmodule  // RX_DESERIALIZER
// Local Variables:
// verilog-library-flags:("-f ../../include.vc")
// End:
