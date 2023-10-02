//                              -*- Mode: Verilog -*-
// Filename        : tap_read_interconnect.sv
// Description     :
// Author          : Stephan Proß
// Update Count    : 0
// Status          : Unknown, Use with caution!

import uart_pkg::*;

module TAP_READ_INTERCONNECT #(
    parameter integer unsigned READ_WIDTH = 32,
    parameter integer unsigned DMI_WIDTH = 41,
    parameter integer unsigned STB_STATUS_WIDTH = 8,
    parameter integer unsigned STB_DATA_WIDTH = 32
) (
    input                         CLK_I,
    input                         RST_NI,
    // TAP signals
    input  logic [  IRLENGTH-1:0] READ_ADDRESS_I,
    output logic [READ_WIDTH-1:0] READ_DATA_O,
    output logic                  READ_VALID_O,
    input  logic                  READ_READY_I,
    output logic [  IRLENGTH-1:0] VALID_ADDRESS_O,

    // Device signals
    output logic                 DMI_READ_READY_O,
    input  logic                 DMI_READ_VALID_I,
    input  logic [DMI_WIDTH-1:0] DMI_READ_DATA_I,

    output logic                        STB0_STATUS_READY_O,
    input  logic                        STB0_STATUS_VALID_I,
    input  logic [STB_STATUS_WIDTH-1:0] STB0_STATUS_I,

    output logic                      STB0_DATA_READY_O,
    input  logic                      STB0_DATA_VALID_I,
    input  logic [STB_DATA_WIDTH-1:0] STB0_DATA_I,

    output logic                        STB1_STATUS_READY_O,
    input  logic                        STB1_STATUS_VALID_I,
    input  logic [STB_STATUS_WIDTH-1:0] STB1_STATUS_I,

    output logic                      STB1_DATA_READY_O,
    input  logic                      STB1_DATA_VALID_I,
    input  logic [STB_DATA_WIDTH-1:0] STB1_DATA_I
);

  logic read_valid;
  assign READ_VALID_O = read_valid;
  logic [READ_WIDTH-1:0] read_data;
  assign READ_DATA_O = read_data;

  always_comb begin : READ_RV_MUX
    DMI_READ_READY_O = 0;
    STB0_STATUS_READY_O = 0;
    STB0_DATA_READY_O = 0;
    STB1_STATUS_READY_O = 0;
    STB1_DATA_READY_O = 0;
    if (!RST_NI) begin
      read_valid = 0;
      read_data  = '0;
    end else begin
      // Process read ready from Read-Arbiter.
      if (READ_READY_I) begin
        case (READ_ADDRESS_I)
          ADDR_DMI: begin
            read_valid = DMI_READ_VALID_I;
            read_data = DMI_READ_DATA_I;
            DMI_READ_READY_O = READ_READY_I;
          end
          ADDR_STB0_CS: begin
            read_valid = STB0_STATUS_VALID_I;
            read_data[$bits(STB0_STATUS_I)-1:0] = STB0_STATUS_I;
            STB0_STATUS_READY_O = READ_READY_I;
          end
          ADDR_STB0_D: begin
            read_valid = STB0_DATA_VALID_I;
            read_data[$bits(STB0_DATA_I)-1:0] = STB0_DATA_I;
            STB0_DATA_READY_O = READ_READY_I;
          end
          ADDR_STB1_CS: begin
            read_valid = STB1_STATUS_VALID_I;
            read_data[$bits(STB1_STATUS_I)-1:0] = STB1_STATUS_I;
            STB1_STATUS_READY_O = READ_READY_I;
          end
          ADDR_STB1_D: begin
            read_valid = STB1_DATA_VALID_I;
            read_data[$bits(STB1_DATA_I)-1:0] = STB1_DATA_I;
            STB0_DATA_READY_O = READ_READY_I;
          end
          ADDR_IDCODE: begin
            read_valid = 1;
            read_data[$bits(IDCODEVALUE)-1:0] = IDCODEVALUE;
          end
          ADDR_DTMCS: begin
            read_valid = 1;
            read_data[$bits(IDCODEVALUE)-1:0] = DTMCS_DEFAULT;
          end

          default: begin
            // Read on invalid address returns zero.
            read_valid = 1;
            read_data  = '0;
          end
        endcase  // case (READ_ADDRESS_I)
      end
    end  // else: !if(!RST_NI)
  end  // block: READ_RV_MUX

  always_ff @(posedge CLK_I) begin : VALID_ADDRESS_PROC
    // Give Read-Arbiter the address of the ready peripheral.
    VALID_ADDRESS_O <= ADDR_NOP;
    if (DMI_READ_VALID_I) begin
      VALID_ADDRESS_O <= ADDR_DMI;
    end else if (STB0_STATUS_VALID_I) begin
      VALID_ADDRESS_O <= ADDR_STB0_CS;
    end else if (STB1_STATUS_VALID_I) begin
      VALID_ADDRESS_O <= ADDR_STB1_CS;
    end else if (STB0_DATA_VALID_I) begin
      VALID_ADDRESS_O <= ADDR_STB0_D;
    end else if (STB1_DATA_VALID_I) begin
      VALID_ADDRESS_O <= ADDR_STB1_D;
    end else begin
      VALID_ADDRESS_O <= ADDR_NOP;
    end
  end

endmodule  // TAP_READ_INTERCONNECT
