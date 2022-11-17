//                              -*- Mode: SystemVerilog -*-
// Filename        : uart_pkg.sv
// Description     : Package containing definitions specific for the UART DTM.
// Author          : Stephan Proß
// Created On      : Thu Nov 17 17:33:46 2022
// Last Modified By: Stephan Proß
// Last Modified On: Thu Nov 17 17:33:46 2022
// Update Count    : 0
// Status          : Unknown, Use with caution!

import dm::*;

package uart_pkg;
  localparam integer IRLENGTH = 5;
  localparam logic [31:0] IDCODEVALUE = 32'h01;
  localparam integer      CMDLENGTH = 8 - IRLENGTH;

  typedef enum            logic [CMD_LENGTH-1:0] {
                                                  CMD_NOP = 3'b000,
                                                  CMD_READ = 3'b001,
                                                  CMD_WRITE = 3'b010,
                                                  CMD_RW = 3'b011,
                                                  CMD_RESET = 3'b100
                                                  } cmd_e;

  typedef enum            logic [IRLENGTH-1:0] {
                                                ADDR_IDCODE = 5'b00001,
                                                ADDR_DTMCS = 5'b10000,
                                                ADDR_DMI = 5'b10001
                                                } addr_e;
  localparam integer      ABITS = 7;
  localparam integer      DMI_REQ_LENGTH = $size(dmi_req_t);
  localparam integer      DMI_RESP_LENGTH = $size(dmi_resp_t);

  typedef enum logic [1:0] {
    DMINoError = 2'h0, DMIReservedError = 2'h1,
    DMIOPFailed = 2'h2, DMIBusy = 2'h3
  } dmi_error_e;

  typedef struct packed {
    logic [31:18] zero1;
    logic         dmihardreset;
    logic         dmireset;
    logic         zero0;
    logic [14:12] idle;
    logic [11:10] dmistat;
    logic [9:4]   abits;
    logic [3:0]   version;
  } dtmcs_t;

endpackage : uart_pkg
