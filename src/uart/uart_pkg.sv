//                              -*- Mode: SystemVerilog -*-
// Filename        : uart_pkg.sv
// Description     : Package containing definitions specific for the UART DTM.
// Author          : Stephan Proß
// Created On      : Thu Nov 17 17:33:46 2022
// Last Modified By: Stephan Proß
// Last Modified On: Thu Nov 17 17:33:46 2022
// Update Count    : 0
// Status          : Unknown, Use with caution!

// import dm::*;

package uart_pkg;
  localparam integer IRLENGTH = 5;
  localparam logic [31:0] IDCODEVALUE = 32'h01;
  localparam integer      CMDLENGTH = 8 - IRLENGTH;

  localparam logic [7:0]  HEADER = 8'h01; // SOF in ASCII

  typedef enum            logic [CMDLENGTH-1:0] {
                                                 CMD_NOP       = 3'b000,
                                                 CMD_READ      = 3'b001,
                                                 CMD_CONT_READ = 3'b010,
                                                 CMD_WRITE     = 3'b011,
                                                 CMD_RESET     = 3'b111
                                                 } cmd_e;

  typedef enum            logic [IRLENGTH-1:0] {
                                                ADDR_NOP     = 5'b00000,
                                                ADDR_IDCODE  = 5'b00001,
                                                ADDR_DTMCS   = 5'b10000,
                                                ADDR_DMI     = 5'b10001,
                                                ADDR_STB0_CS = 5'b10100,
                                                ADDR_STB0_D  = 5'b10101,
                                                ADDR_STB1_CS = 5'b10110,
                                                ADDR_STB1_D  = 5'b10111
                                                } addr_e;

  const integer unsigned  WRITE_LENGTHS [logic[IRLENGTH-1:0]] =
                '{
                  ADDR_IDCODE  : 32,
                  ADDR_DTMCS   : 32,
                  ADDR_DMI     : 41,
                  ADDR_STB0_CS : 8,
                  ADDR_STB0_D  : 32,
                  ADDR_STB1_CS : 8,
                  ADDR_STB1_D  : 32
                  };

  const integer unsigned  READ_LENGTHS [logic[IRLENGTH-1:0]] =
                '{
                  ADDR_IDCODE  : 32,
                  ADDR_DTMCS   : 32,
                  ADDR_DMI     : 34,
                  ADDR_STB0_CS : 8,
                  ADDR_STB0_D  : 32,
                  ADDR_STB1_CS : 8,
                  ADDR_STB1_D  : 32
                  };


  localparam integer unsigned ABITS = 7;

  typedef enum            logic [1:0] {
                                       DMINoError = 2'h0, DMIReservedError = 2'h1,
                                       DMIOPFailed = 2'h2, DMIBusy = 2'h3
                                       } dmi_error_e;

  typedef struct          packed {
    logic [31:18]         zero1;
    logic                 dmihardreset;
    logic                 dmireset;
    logic                 zero0;
    logic [14:12]         idle;
    logic [11:10]         dmistat;
    logic [9:4]           abits;
    logic [3:0]           version;
  } dtmcs_t;

  localparam              dtmcs_t DTMCS_DEFAULT = '{
                                                    zero1 : '0,
                                                    dmihardreset : 0,
                                                    dmireset : 0,
                                                    zero0 : 0,
                                                    idle : 3'b001,
                                                    dmistat : DMINoError,
                                                    abits : ABITS,
                                                    version : 4'h01
                                                    };



endpackage : uart_pkg
