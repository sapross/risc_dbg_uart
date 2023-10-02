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
  logic [IRLENGTH-1:0] addr, addr_next;
  logic [CMDLENGTH-1:0] cmd, cmd_next;

  typedef enum {
    st_idle,
    st_handover,
    st_wait_ack
  } state_t;
  state_t state, state_next;

  always_ff @(posedge CLK_I) begin : FSM
    if (!RST_NI) begin
      state <= st_idle;
      addr  <= '0;
      cmd   <= CMD_NOP;

    end else begin
      state <= state_next;
      addr  <= addr_next;
      cmd   <= cmd_next;
    end
  end


  assign BUSY_O = state == !st_idle ? 1 : 0;

  always_comb begin : DECODER
    if (!RST_NI) begin
      state_next = st_idle;
      addr_next = '0;
      cmd_next = CMD_NOP;

      READ_ARBITER_VALID_O = 0;
      READ_ADDRESS_O = '0;
      READ_COMMAND_O = CMD_NOP;

      WRITE_ARBITER_VALID_O = 0;
      WRITE_ADDRESS_O = '0;
      WRITE_COMMAND_O = CMD_NOP;
    end else begin
      READ_ARBITER_VALID_O = 0;
      READ_ADDRESS_O = '0;
      READ_COMMAND_O = CMD_NOP;

      WRITE_ARBITER_VALID_O = 0;
      WRITE_ADDRESS_O = '0;
      WRITE_COMMAND_O = CMD_NOP;
      case (state)
        st_idle: begin
          // Process read data and decode cmd & raddr.
          if (READ_I && CMD_REC_I) begin
            addr_next  = DATA_REC_I[IRLENGTH-1:0];
            cmd_next   = DATA_REC_I[7:IRLENGTH];
            state_next = st_handover;
          end
        end
        st_handover: begin
          case (cmd)
            // Reset is communicated with the Arbiters.
            CMD_RESET: begin
              WRITE_ARBITER_VALID_O = 1;
              WRITE_COMMAND_O = CMD_RESET;
              WRITE_ADDRESS_O = ADDR_IDCODE;

              READ_ARBITER_VALID_O = 1;
              READ_COMMAND_O = CMD_RESET;
              READ_ADDRESS_O = addr;
              if (READ_ARBITER_READY_I && WRITE_ARBITER_READY_I) begin
                state_next = st_wait_ack;
              end
            end
            // Read cmds do not change WRITE_COMMAND_O and progress.
            CMD_READ: begin
              READ_ARBITER_VALID_O = 1;
              READ_COMMAND_O = CMD_READ;
              READ_ADDRESS_O = addr;
              if (READ_ARBITER_READY_I) begin
                state_next = st_wait_ack;
              end
            end
            CMD_CONT_READ: begin
              READ_ARBITER_VALID_O = 1;
              READ_COMMAND_O = CMD_CONT_READ;
              READ_ADDRESS_O = addr;
              if (READ_ARBITER_READY_I) begin
                state_next = st_wait_ack;
              end
            end
            // Only CMD_WRITE changes write variables.
            CMD_WRITE: begin
              WRITE_ARBITER_VALID_O = 1;
              WRITE_COMMAND_O = CMD_WRITE;
              WRITE_ADDRESS_O = addr;
              if (WRITE_ARBITER_READY_I) begin
                state_next = st_wait_ack;
              end
            end
            default: state_next = st_idle;
          endcase  // case ( cmd )
        end  // case: st_handover
        st_wait_ack: begin
          BUSY_O = 1;
          if (!WRITE_ARBITER_READY_I && !READ_ARBITER_READY_I) begin
            state_next = st_idle;
          end
        end

        default: state_next = st_idle;
      endcase  // case (state)

    end  // else: !if(!RST_NI)
  end  // block: CMD_DECODE

endmodule  // CMD_DECODER
// Local Variables:
// verilog-library-flags:("-f ../../include.vc")
// End:
