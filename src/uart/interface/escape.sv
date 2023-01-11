//                              -*- Mode: Verilog -*-
// Filename        : escape.sv
// Description     : Escape module aggregating RX- and TX-Escape modules.
// Author          : Stephan Proß
// Created On      : Mon Jan  9 17:00:32 2023
// Last Modified By: Stephan Proß
// Last Modified On: Mon Jan  9 17:00:32 2023
// Update Count    : 0
// Status          : Unknown, Use with caution!

module EscapeFilter
#(
  parameter logic [7:0] ESC = 8'hB1
)
 (
  input logic        CLK_I,
  input logic        RST_NI,

  // RX
  input logic [7:0]  DATA_REC_I,
  input logic        RX_EMPTY_I,
  output logic       READ_O,
  // TX
  input logic        TX_READY_I,
  output logic [7:0] DATA_SEND_O,
  output logic       WRITE_O,

   // Signals from/to TAP
  input logic        READ_I,
  output logic       CMD_REC_O,
  output logic [7:0] DATA_REC_O,

  input logic        CMD_SEND_I,
  input logic [7:0]  CMD_I,
  input logic        WRITE_I,
  input logic [7:0]  DATA_SEND_I,

  output logic       RX_EMPTY_O,
  output logic       TX_READY_O
);

  RX_Escape #(.ESC(ESC))
  rx_esc (
          .CLK_I      (CLK_I),
          .RST_NI     (RST),
          .DATA_REC_I (DATA_REC_I),
          .RX_EMPTY_I (RX_EMPTY_I),
          .READ_O     (READ_O),
          .READ_I     (READ_I),
          .RX_EMPTY_O (RX_EMPTY_O),
          .COMMAND_O  (CMD_REC_I),
          .DATA_REC_O (DATA_REC_O)
          );
  TX_Escape #(.ESC(ESC))
  tx_esc (
          .CLK_I            (CLK_I),
          .RST_NI           (RST),

          .TX_READY_I       (TX_READY_I),
          .DATA_SEND_O      (DATA_SEND_O),
          .WRITE_O          (WRITE_O),

          .TX_READY_O       (TX_READY_O),
          .DATA_SEND_I      (DATA_SEND_I),
          .WRITE_I          (WRITE_I),
          .WRITE_COMMAND_I  (CMD_SEND_I),
          .COMMAND_I        (CMD_I)
          );
endmodule // Escape
