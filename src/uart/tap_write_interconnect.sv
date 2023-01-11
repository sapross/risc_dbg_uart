//                              -*- Mode: Verilog -*-
// Filename        : tap_write_interconnect.sv
// Description     :
// Author          : Stephan Proß
// Update Count    : 0
// Status          : Unknown, Use with caution!

import uart_pkg::*;

module TAP_WRITE_INTERCONNECT
  #(
    parameter integer unsigned WRITE_WIDTH = 32
    )
  (
 input                               CLK_I,
 input                               RST_NI,

 input logic [IRLENGTH-1:0]          WRITE_ADDRESS_I,
 input logic [WRITE_WIDTH-1:0]       WRITE_DATA_I,
 input logic                         WRITE_VALID_I,
 output logic                        WRITE_READY_O,

 input logic                         DMI_WRITE_READY_I,
 output logic                        DMI_WRITE_VALID_O,
 output logic                        DMI_WRITE_DATA_O,

 input logic                         STB0_CONTROL_READY_I,
 output logic                        STB0_CONTROL_VALID_O,
 output logic [$bits(control_t)-1:0] STB0_CONTROL_O,

 input logic                         STB0_DATA_READY_I,
 output logic                        STB0_DATA_VALID_O,
 output logic [TRB_WIDTH-1:0]        STB0_DATA_O,

 input logic                         STB1_CONTROL_READY_I,
 output logic                        STB1_CONTROL_VALID_O,
 output logic [$bits(control_t)-1:0] STB1_CONTROL_O,

 input logic                         STB1_DATA_READY_I,
 output logic                        STB1_DATA_VALID_O,
 output logic [TRB_WIDTH-1:0]        STB1_DATA_O
   ) ;

  logic write_ready;
  assign WRITE_READY_O = write_ready;

  always_comb begin : WRITE_RV_MUX
      DMI_WRITE_VALID_O = 0;
      DMI_WRITE_DATA_O  ='0;

      STB0_CONTROL_VALID_O = 0;
      STB0_CONTROL_O  ='0;
      STB0_DATA_VALID_O = 0;
      STB0_DATA_O  ='0;

      STB1_CONTROL_VALID_O = 0;
      STB1_CONTROL_O  ='0;
      STB1_DATA_VALID_O = 0;
      STB1_DATA_O  ='0;
      write_ready = 0;

    if(RST_NI) begin
      case (WRITE_ADDRESS_I)
        ADDR_DMI : begin
          DMI_WRITE_VALID_O = WRITE_VALID_I;
          write_ready = DMI_WRITE_READY_I;
          DMI_WRITE_DATA_O = WRITE_DATA_I[$bits(DMI_WRITE_DATA_O)-1:0];
        end
        ADDR_STB0_CS : begin
          STB0_CONTROL_VALID_O = WRITE_VALID_I;
          write_ready = STB0_CONTROL_READY_I;
          STB0_CONTROL_O = WRITE_DATA_I[$bits(STB0_CONTROL_O)-1:0];
        end
        ADDR_STB0_D : begin
          STB0_DATA_VALID_O = WRITE_VALID_I;
          write_ready = STB0_DATA_READY_I;
          STB0_DATA_O = WRITE_DATA_I[$bits(STB0_DATA_O)-1:0];
        end
        ADDR_STB1_CS : begin
          STB1_CONTROL_VALID_O = WRITE_VALID_I;
          write_ready = STB1_CONTROL_READY_I;
          STB1_CONTROL_O = WRITE_DATA_I[$bits(STB1_CONTROL_O)-1:0];
        end
        ADDR_STB1_D : begin
          STB1_DATA_VALID_O = WRITE_VALID_I;
          write_ready = STB1_DATA_READY_I;
          STB1_DATA_O = WRITE_DATA_I[$bits(STB1_DATA_O)-1:0];
        end
        default : begin
          // Writes to addresses unkown to the interconnect
          // always "succeed" to prevent lock-up of system.
          write_ready = 1;
        end

      endcase // case (write_address)

    end
  end
endmodule // TAP_WRITE_INTERCONNECT
