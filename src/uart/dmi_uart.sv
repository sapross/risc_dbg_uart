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
                 input logic                         TAP_READ_READY_I,
                 output logic [$bits(dmi_req_t)-1:0] TAP_READ_DATA_O,
                 output logic                        TAP_READ_VALID_O,

                 output logic                        TAP_WRITE_READY_O,
                 input logic                         TAP_WRITE_VALID_I,
                 input logic [$bits(dmi_req_t)-1:0]  TAP_WRITE_DATA_I,

                 // Ready/Valid Bus for DM
                 output logic                        DMI_RESP_READY_O,
                 input logic                         DMI_RESP_VALID_I,
                 input [$bits(dmi_resp_t)-1:0]       DMI_RESP_I,

                 input logic                         DMI_REQ_READY_I,
                 output logic                        DMI_REQ_VALID_O,
                 output [$bits(dmi_req_t)-1:0]       DMI_REQ_O
                 ) ;

  // DMI_JTAG (alongside OpenOCD) define a different dmi_req datatype.
  // Requires conversion to the data-type defined in dm_pkg.
  typedef struct                                     packed {
    logic [6:0]                                      addr;
    logic [31:0]                                     data;
    logic [1:0]                                      op;
  } dmi_t;
  dmi_t dmi_req;

  dmi_req_t conv_req;
  assign conv_req.addr = dmi_req.addr;
  assign conv_req.data = dmi_req.data;
  assign conv_req.op = dtm_op_e'(dmi_req.op);

  assign DMI_REQ_O = conv_req;

  dmi_t tap_dmi_req;
  assign tap_dmi_req = dmi_t'(TAP_WRITE_DATA_I);

  // DMI-JTAG uses a different format to answer the TAP.
  typedef struct                                     packed {
    logic [6:0]                                      addr;
    logic [31:0]                                     data;
    dmi_error_e dmi_error;
  } tap_resp_t;

  // DMI output to the tap consists of the following data.
  // - Requeset address (effectively unused by the tap)
  // - Response data
  // - 2-Bit error code.
  tap_resp_t tap_dmi_resp;

  dmi_resp_t dmi_resp;
  assign tap_dmi_resp.addr = dmi_req.addr;
  assign tap_dmi_resp.data = dmi_resp.data;
  assign tap_dmi_resp.dmi_error = DMINoError;

  assign TAP_READ_DATA_O = tap_dmi_resp;

  logic                                              do_read;
  logic                                              do_write;
  logic                                              do_end;

  assign DMI_REQ_VALID_O = do_read || do_write;

  always_ff @(posedge CLK_I) begin : DMI_WRITE
    if(!RST_NI) begin
      TAP_WRITE_READY_O <= 0;
      dmi_req <= '0;
      dmi_resp <= '0;

      do_read <= 0;
      do_write <= 0;
      do_end <= 0;

    end
    else begin
      TAP_WRITE_READY_O <= 0;
      if (do_end) begin
        if (!TAP_WRITE_VALID_I) begin
          do_end <= 0;
        end
      end
      else if (do_read) begin
        if (DMI_RESP_VALID_I) begin
          do_read <= 0;
          do_end <= 1;
          dmi_resp <= DMI_RESP_I;
        end
      end
      else if (do_write) begin
        if(DMI_RESP_VALID_I) begin
          do_write <= 0;
          do_end <= 1;
        end
      end
      else begin
        if (TAP_WRITE_VALID_I) begin
          TAP_WRITE_READY_O <= 1;
          dmi_req <= tap_dmi_req;
          if (tap_dmi_req.op == DTM_READ) begin
            do_read <= 1;
          end
          else if (tap_dmi_req.op == DTM_WRITE) begin
            do_write <= 1;
          end
        end
      end
    end
  end

  // TAP read process. As the data signals are valid all the time
  // read requests are simply answered by setting valid to high.
  always_ff @(posedge CLK_I) begin : TAP_READ
    if(!RST_NI) begin
      TAP_READ_VALID_O <= 0;
      DMI_RESP_READY_O <= 0;
    end
    else begin
      DMI_RESP_READY_O <= 1;
      // Do not answer read requests by tap if there is an outstanding
      // dmi operation.
      if (!do_read && !do_write) begin
        if (TAP_READ_READY_I) begin
          TAP_READ_VALID_O <= 1;
        end
        else begin
          TAP_READ_VALID_O <= 0;
        end
      end
    end
  end

endmodule // DMI_UART
