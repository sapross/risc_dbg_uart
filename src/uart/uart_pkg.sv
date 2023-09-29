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
  localparam logic [7:0]  ESC = 8'hA0;

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

  localparam integer unsigned WLEN_IDCODE  = 32;
  localparam integer unsigned WLEN_DTMCS   = 32;
  localparam integer unsigned WLEN_DMI     = 41;
  localparam integer unsigned WLEN_STB0_CS = 8;
  localparam integer unsigned WLEN_STB0_D  = 32;
  localparam integer unsigned WLEN_STB1_CS = 8;
  localparam integer unsigned WLEN_STB1_D  = 32;

  function integer unsigned get_write_length(input logic [IRLENGTH-1:0] addr);
    case(addr)
      ADDR_IDCODE: begin
        return WLEN_IDCODE;
      end
      ADDR_DTMCS: begin
        return WLEN_DTMCS;
      end
      ADDR_DMI: begin
        return WLEN_DMI;
      end
      ADDR_STB0_CS: begin
        return WLEN_STB0_CS;
      end
      ADDR_STB0_D: begin
        return WLEN_STB0_D;
      end
      ADDR_STB1_CS: begin
        return WLEN_STB1_CS;
      end
      ADDR_STB1_D: begin
        return WLEN_STB1_D;
      end
      default : begin
        return 8;
      end
    endcase
  endfunction // get_write_length

  localparam integer unsigned RLEN_IDCODE  = 32;
  localparam integer unsigned RLEN_DTMCS   = 32;
  localparam integer unsigned RLEN_DMI     = 41;
  localparam integer unsigned RLEN_STB0_CS = 8;
  localparam integer unsigned RLEN_STB0_D  = 32;
  localparam integer unsigned RLEN_STB1_CS = 8;
  localparam integer unsigned RLEN_STB1_D  = 32;

  function integer unsigned get_read_length(input logic [IRLENGTH-1:0] addr);
    case(addr)
      ADDR_IDCODE: begin
        return RLEN_IDCODE;
      end
      ADDR_DTMCS: begin
        return RLEN_DTMCS;
      end
      ADDR_DMI: begin
        return RLEN_DMI;
      end
      ADDR_STB0_CS: begin
        return RLEN_STB0_CS;
      end
      ADDR_STB0_D: begin
        return RLEN_STB0_D;
      end
      ADDR_STB1_CS: begin
        return RLEN_STB1_CS;
      end
      ADDR_STB1_D: begin
        return RLEN_STB1_D;
      end
      default : begin
        return 8;
      end
    endcase
  endfunction // get_read_length

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
                                                    idle : 3'd1,
                                                    dmistat : DMINoError,
                                                    abits : 6'd7,
                                                    version : 4'd1
                                                    };



endpackage : uart_pkg
