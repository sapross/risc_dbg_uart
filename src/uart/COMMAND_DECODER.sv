//-----------------------------------------------------------------------------
// Title         : COMMAND_DECODER
// Project       : riscv-dbg-uart
//-----------------------------------------------------------------------------
// File          : COMMAND_DECODER.sv
// Author        : Stephan Proß  <spross@S-PC>
// Created       : 29.09.2023
// Last modified : 29.09.2023
//-----------------------------------------------------------------------------
// Description :
// Decoder for commands received over UART.
//------------------------------------------------------------------------------
// Modification history :
// 29.09.2023 : created
//-----------------------------------------------------------------------------

import uart_pkg::*;

module COMMAND_DECODER (  /*AUTOARG*/
    // Outputs
    BUSY_O,
    WRITE_COMMAND_O,
    WRITE_ADDRESS_O,
    READ_COMMAND_O,
    READ_ADDRESS_O,
    READ_ARBITER_VALID_O,
    WRITE_ARBITER_VALID_O,
    // Inputs
    CLK_I,
    RST_NI,
    READ_I,
    CMD_REC_I,
    DATA_REC_I,
    READ_ARBITER_READY_I,
    WRITE_ARBITER_READY_I
);
  input logic CLK_I;
  input logic RST_NI;
  input logic READ_I;
  input logic CMD_REC_I;
  input logic [7:0] DATA_REC_I;


  output logic BUSY_O;

  output logic [CMDLENGTH-1:0] WRITE_COMMAND_O;
  output logic [IRLENGTH-1:0] WRITE_ADDRESS_O;

  output logic [CMDLENGTH-1:0] READ_COMMAND_O;
  output logic [IRLENGTH-1:0] READ_ADDRESS_O;

  // Decoder to Read-Arbiter ready-valid
  input logic READ_ARBITER_READY_I;
  output logic READ_ARBITER_VALID_O;

  // Decoder to Write-Arbiter ready-valid
  input logic WRITE_ARBITER_READY_I;
  output logic WRITE_ARBITER_VALID_O;

  // Signals for easier address and command access.
  logic [ IRLENGTH-1:0] address;
  logic [CMDLENGTH-1:0] command;

  always_ff @(posedge CLK_I) begin : DECODER
    if (!RST_NI) begin
      BUSY_O <= 0;
      address <= '0;
      command <= CMD_NOP;

      READ_ARBITER_VALID_O <= 0;
      READ_ADDRESS_O <= '0;
      READ_COMMAND_O <= CMD_NOP;

      WRITE_ARBITER_VALID_O <= 0;
      WRITE_ADDRESS_O <= '0;
      WRITE_COMMAND_O <= CMD_NOP;

    end else begin

      READ_ARBITER_VALID_O  <= 0;
      WRITE_ARBITER_VALID_O <= 0;
      // Process read data and decode command & address.
      if (READ_I && CMD_REC_I) begin
        BUSY_O  <= 1;
        address <= DATA_REC_I[IRLENGTH-1:0];
        command <= DATA_REC_I[7:IRLENGTH];
      end
      if (BUSY_O) begin
        case (command)
          // Reset is communicated with the Arbiters.
          CMD_RESET: begin
            WRITE_ARBITER_VALID_O <= 1;
            WRITE_COMMAND_O <= CMD_RESET;
            WRITE_ADDRESS_O <= ADDR_IDCODE;

            READ_ARBITER_VALID_O <= 1;
            READ_COMMAND_O <= CMD_RESET;
            READ_ADDRESS_O <= address;
            if (READ_ARBITER_READY_I && WRITE_ARBITER_READY_I) begin
              BUSY_O <= 0;
            end
          end

          // Read commands do not change WRITE_COMMAND_O and progress.
          CMD_READ: begin
            READ_ARBITER_VALID_O <= 1;
            READ_COMMAND_O <= CMD_READ;
            READ_ADDRESS_O <= address;
            if (READ_ARBITER_READY_I) begin
              BUSY_O <= 0;
            end
          end
          CMD_CONT_READ: begin
            READ_ARBITER_VALID_O <= 1;
            READ_COMMAND_O <= CMD_CONT_READ;
            READ_ADDRESS_O <= address;
            if (READ_ARBITER_READY_I) begin
              BUSY_O <= 0;
            end
          end

          // Only CMD_WRITE changes write variables.
          CMD_WRITE: begin
            WRITE_ARBITER_VALID_O <= 1;
            WRITE_COMMAND_O <= CMD_WRITE;
            WRITE_ADDRESS_O <= address;
            if (WRITE_ARBITER_READY_I) begin
              BUSY_O <= 0;
            end
          end
          default: begin
            BUSY_O <= 0;
          end
        endcase  // case ( command )
      end  // if (READ_I && CMD_REC_I)
    end  // else: !if(!RST_NI)
  end  // block: CMD_DECODE

endmodule  // COMMAND_DECODER
// Local Variables:
// verilog-library-flags:("-f ../../include.vc")
// End:
