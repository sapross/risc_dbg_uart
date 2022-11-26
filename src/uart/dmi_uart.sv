//                              -*- Mode: SystemVerilog -*-
// Filename        : dmi_uart.sv
// Description     : Debug Module interface connecting the UART-TAP with the DM via a Ready-Valid Bus.
// Author          : Stephan Proß
// Created On      : Fri Nov 18 08:52:11 2022
// Last Modified By: Stephan Proß
// Last Modified On: Fri Nov 18 08:52:11 2022
// Update Count    : 0
// Status          : Unknown, Use with caution!

import uart_pkg::*;
import dm::*;


module DMI_UART (/*AUTOARG*/

                 input logic                         CLK_I,
                 input logic                         RST_NI,

                 // TAP Signals
                 input logic                         TAP_READ_I,
                 input logic                         TAP_WRITE_I,
                 input logic [$bits(dmi_req_t)-1:0]  DMI_I,
                 output logic [$bits(dmi_req_t)-1:0] DMI_O,
                 output logic                        DONE_O,
                 input logic                         DMI_HARD_RESET_I,

                 // Ready/Valid Bus for DM
                 input logic                         DMI_RESP_VALID_I,
                 output logic                        DMI_RESP_READY_O,
                 input [$bits(dmi_resp_t)-1:0]       DMI_RESP_I,

                 output logic                        DMI_REQ_VALID_O,
                 input logic                         DMI_REQ_READY_I,
                 output [$bits(dmi_req_t)-1:0]       DMI_REQ_O,

                 output logic                        DMI_RST_NO
                 ) ;

  typedef enum                                           {
                                                          st_idle,
                                                          st_read,
                                                          st_write,
                                                          st_read_dmi,
                                                          st_wait_read_dmi,
                                                          st_write_dmi,
                                                          st_wait_write_dmi,
                                                          st_wait_ack,
                                                          st_reset
                                                          } state_t;


  // For easier state manipulation, dmi-request and -response are packed together.
  typedef struct                                         packed {
    dmi_req_t dmi_req;
    dmi_resp_t dmi_resp;
    state_t state;
  } fsm_t;

  fsm_t fsm, fsm_next;
  assign DMI_REQ_O = fsm.dmi_req;

  logic                                                  dmi_resp_ready;
  assign DMI_RESP_READY_O = dmi_resp_ready;

  logic                                                  dmi_req_valid;
  assign DMI_REQ_VALID_O = dmi_req_valid;

  logic                                                  done;
  assign DONE_O = done;

  dmi_req_t tap_dmi_req;
  assign tap_dmi_req = DMI_I;

  // DMI-JTAG uses a different format to answer the TAP.
  typedef struct                                         packed {
    logic [6:0]                                          addr;
    logic [31:0]                                         data;
    dmi_error_e dmi_error;
  } tap_resp_t;

  // DMI output to the tap consists of the following data.
  // - Requeset address (effectively unused by the tap)
  // - Response data
  // - 2-Bit error code.
  tap_resp_t tap_dmi_resp;
  assign DMI_O = tap_dmi_resp;
  assign tap_dmi_resp.addr = fsm.dmi_req.addr;
  assign tap_dmi_resp.data = fsm.dmi_resp.data;
  assign tap_dmi_resp.dmi_error = DMINoError;

  // Passthrough of the hard reset signals from the TAP.
  assign DMI_RST_NO = ~DMI_HARD_RESET_I;

  // Synchronous state transitions.
  always_ff @(posedge CLK_I) begin : FSM_CORE
    if (!RST_NI) begin
      fsm.state <= st_idle;
      fsm.dmi_req <= '0;
      fsm.dmi_resp <= '0;
    end
    else begin
      fsm <= fsm_next;
    end
  end

  // Asynchronous next state evaluation.
  always_comb begin : FSM
    fsm_next = fsm;
    if (!RST_NI) begin
      fsm_next.state = st_idle;
      dmi_resp_ready = 0;
      dmi_req_valid = 0;
      done = 0;
    end
    else begin
      // We are always ready to receive a response from the DM.
      // Requests are only valid if issued by the TAP.
      dmi_resp_ready = 1;
      dmi_req_valid = 0;
      done = 0;

      case (fsm.state)
        st_idle: begin
          // Wait for request from TAP or goto reset state on reset signal.
          if (DMI_HARD_RESET_I == 1) begin
            fsm_next.state = st_reset;
          end
          else begin
            // Only the states read and write exist, triggered exclusively by the
            // corresponding input signals.
            if (TAP_READ_I == 1 && TAP_WRITE_I == 0) begin
              fsm_next.state = st_read;
            end
            else if (TAP_READ_I == 0 && TAP_WRITE_I == 1) begin
              fsm_next.state = st_write;
            end
          end // else: !if(DMI_HARD_RESET_I == 1)
        end // case: st_idle

        st_read: begin
          // DMI_O is in the correct state by default, therefore
          // only waiting for the ack from TAP remains.
          fsm_next.state = st_wait_ack;
        end

        st_write: begin
          // Apply DMI-Request from the TAP to local variable.
          fsm_next.dmi_req = tap_dmi_req;
          // Determine, whether a dmi-write or -read command has been issued.
          if (tap_dmi_req.op == DTM_READ) begin
            fsm_next.state = st_read_dmi;
          end
          else if (tap_dmi_req.op == DTM_WRITE) begin
            fsm_next.state = st_write_dmi;
          end
          else begin
            // Even if the command is invalid, we must wait for ack from TAP.
            fsm_next.state = st_wait_ack;
          end

        end

        st_read_dmi: begin
          // DMI-request of the state machine has changed to the value from TAP.
          // Request is now valid.
          dmi_req_valid = 1;
          // Wait until DM is ready to read.
          if (DMI_REQ_READY_I == 1) begin
            fsm_next.state = st_wait_read_dmi;
          end
        end

        st_wait_read_dmi: begin
          // Wait until response from DM is valid.
          if (DMI_RESP_VALID_I == 1) begin
            // Apply response to local register and wait for ack from TAP.
            fsm_next.dmi_resp = DMI_RESP_I;
            fsm_next.state = st_wait_ack;
          end

        end
        st_write_dmi: begin
          // Functionally equivalent to the st_read_dmi state. Only difference is the state following.
          dmi_req_valid = 1;
          if (DMI_REQ_READY_I == 1) begin
            // Wait until DM is ready to read.
            fsm_next.state = st_wait_write_dmi;
          end
        end

        st_wait_write_dmi: begin
          // Wait until response from DM is valid.
          if (DMI_RESP_VALID_I == 1) begin
            fsm_next.state = st_wait_ack;
            // Unlike st_wait_read_dmi, response is not copied into local register.
          end
        end

        st_wait_ack: begin
          // Signal TAP that we have finished command.
          done = 1;
          if (TAP_WRITE_I == 0 && TAP_READ_I == 0) begin
            // Lowering of both write and read inputs signifies ack.
            fsm_next.state = st_idle;
          end
        end

        st_reset: begin
          // Reset local dmi-req and -resp registers.
          fsm_next.state = st_idle;
          fsm_next.dmi_req = '0;
          fsm_next.dmi_resp = '0;
        end

        default : begin
          fsm_next.state = st_idle;
        end

      endcase // case (fsm.state)
    end // else: !if(!RST_NI)
  end // block: FSM

endmodule // DMI_UART