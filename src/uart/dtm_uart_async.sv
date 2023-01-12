// Filename        : escape.sv
// Description     : Escape module aggregating RX- and TX-Escape modules.
// Author          : Stephan Proß
// Created On      : Mon Jan  9 17:00:32 2023
// Last Modified By: Stephan Proß
// Last Modified On: Mon Jan  9 17:00:32 2023
// Update Count    : 0
// Status          : Unknown, Use with caution!

import uart_pkg::*;

module DTM_UART_Async
#(
  parameter logic [7:0] ESC = 8'hB1,
  parameter integer     CLK_RATE = 100*10**6,
  parameter integer     BAUD_RATE = 115200,
  parameter integer     DMI_WIDTH = 41,
  parameter integer     STB_CONTROL_WIDTH = 8,
  parameter integer     STB_STATUS_WIDTH = 8,
  parameter integer     STB_DATA_WIDTH = 32
)
 (
  input logic                          CLK_I,
  input logic                          RST_NI,

  // Second Channel
  input logic                          RX_I,
  output logic                         RX2_O,
  output logic                         TX_O,
  input logic                          TX2_I,

  input logic                          DMI_RESP_VALID_I,
  output logic                         DMI_RESP_READY_O,
  input [$bits(dmi_resp_t)-1:0]        DMI_RESP_I,
  output logic                         DMI_REQ_VALID_O,
  input logic                          DMI_REQ_READY_I,
  output [$bits(dmi_req_t)-1:0]        DMI_REQ_O,


  output logic                         STB0_STATUS_READY_O,
  input logic                          STB0_STATUS_VALID_I,
  input logic [STB_STATUS_WIDTH-1:0]   STB0_STATUS_I,
  input logic                          STB0_CONTROL_READY_I,
  output logic                         STB0_CONTROL_VALID_O,
  output logic [STB_CONTROL_WIDTH-1:0] STB0_CONTROL_O,

  output logic                         STB0_DATA_READY_O,
  input logic                          STB0_DATA_VALID_I,
  input logic [STB_DATA_WIDTH-1:0]     STB0_DATA_I,
  input logic                          STB0_DATA_READY_I,
  output logic                         STB0_DATA_VALID_O,
  output logic [STB_DATA_WIDTH-1:0]    STB0_DATA_O,

  output logic                         STB1_STATUS_READY_O,
  input logic                          STB1_STATUS_VALID_I,
  input logic [STB_STATUS_WIDTH-1:0]   STB1_STATUS_I,
  input logic                          STB1_CONTROL_READY_I,
  output logic                         STB1_CONTROL_VALID_O,
  output logic [STB_CONTROL_WIDTH-1:0] STB1_CONTROL_O,

  output logic                         STB1_DATA_READY_O,
  input logic                          STB1_DATA_VALID_I,
  input logic [STB_DATA_WIDTH-1:0]     STB1_DATA_I,
  input logic                          STB1_DATA_READY_I,
  output logic                         STB1_DATA_VALID_O,
  output logic [STB_DATA_WIDTH-1:0]    STB1_DATA_O

);

  logic                                tx_write;
  logic [7:0]                          tx_data;
  logic                                uintf_ready;

  logic                                rx_read;
  logic [7:0]                          rx_data;
  logic                                uintf_empty;
  logic                                uintf_full;

  logic                                rx0, rx1;
  logic                                tx0, tx1;

  logic                                sw_channel;
  logic                                channel;

  UART #(
         .CLK_RATE(CLK_RATE),
         .BAUD_RATE(BAUD_RATE)
         ) uart_1
    (
     .CLK_I(CLK_I),
     .RST_NI(RST_NI),
     .WE_I(tx_write),
     .DSEND_I(tx_data),
     .RE_I(rx_read),
     .DREC_O(rx_data),
     .RX_I(RX_I),
     .RX2_O(RX2_O),
     .TX_O(TX_O),
     .TX2_I(TX2_I),
     .TX_READY_O(uintf_ready),
     .RX_EMPTY_O(uintf_empty),
     .RX_FULL_O(uintf_full),
     .SW_CHANNEL_I( 1'b0),
     .CHANNEL_O(channel)
     );

  logic                                tap_rx_read;
  logic [7:0]                          tap_rx_data;
  logic                                tap_rx_cmd;
  logic                                tap_rx_empty;

  RX_Escape #(.ESC(ESC))
  rx_esc (
          .CLK_I      (CLK_I),
          .RST_NI     (RST_NI),

          .DATA_REC_I (rx_data),
          .RX_EMPTY_I (uintf_empty),
          .READ_O     (rx_read),

          .READ_I     (tap_rx_read),
          .RX_EMPTY_O (tap_rx_empty),
          .COMMAND_O  (tap_rx_cmd),
          .DATA_REC_O (tap_rx_data)
          );

  logic                                tap_tx_write;
  logic [7:0]                          tap_tx_data;
  logic                                tap_tx_cmd_write;
  logic [7:0]                          tap_tx_cmd;
  logic                                tap_tx_ready;

  TX_Escape #(.ESC(ESC))
  tx_esc (
          .CLK_I            (CLK_I),
          .RST_NI           (RST_NI),

          .TX_READY_I       (uintf_ready && !channel),
          .DATA_SEND_O      (tx_data),
          .WRITE_O          (tx_write),

          .TX_READY_O       (tap_tx_ready),
          .DATA_SEND_I      (tap_tx_data),
          .WRITE_I          (tap_tx_write),
          .WRITE_COMMAND_I  (tap_tx_cmd_write),
          .COMMAND_I        (tap_tx_cmd)
          );

  logic [IRLENGTH-1:0]                 tap_write_address;
  logic [DMI_WIDTH-1:0]                    tap_write_data;
  logic                                tap_write_ready;
  logic                                tap_write_valid;


  logic [IRLENGTH-1:0]                 tap_read_address;
  logic [DMI_WIDTH-1:0]                    tap_read_data;
  logic                                tap_read_ready;
  logic                                tap_read_valid;
  logic [IRLENGTH-1:0]                 tap_valid_address;

  DMI_UART_TAP_ASYNC
  #(
    .WIDTH(DMI_WIDTH)
    )
  tap_async
  (
   .CLK_I (CLK_I),
   .RST_NI (RST_NI),
   .READ_O(tap_rx_read),
   .DATA_REC_I(tap_rx_data),
   .RX_EMPTY_I(tap_rx_empty),
   .CMD_REC_I(tap_rx_cmd),
   .TX_READY_I(tap_tx_ready),
   .WRITE_O(tap_tx_write),
   .DATA_SEND_O(tap_tx_data),
   .SEND_COMMAND_O(tap_tx_cmd_write),
   .COMMAND_O(tap_tx_cmd),

   .DMI_HARD_RESET_O(),
   .DMI_ERROR_I    (2'b00),

   .WRITE_ADDRESS_O(tap_write_address),
   .WRITE_DATA_O(tap_write_data),
   .WRITE_VALID_O(tap_write_valid),
   .WRITE_READY_I(tap_write_ready),

   .READ_ADDRESS_O(tap_read_address),
   .READ_DATA_I(tap_read_data),
   .READ_VALID_I(tap_read_valid),
   .READ_READY_O(tap_read_ready),
   .VALID_ADDRESS_I(tap_valid_address)
   );

  logic                          dmi_read_ready;
   logic                         dmi_read_valid;
   logic [DMI_WIDTH-1:0]         dmi_read_data;


  TAP_READ_INTERCONNECT
    #(
      .READ_WIDTH(DMI_WIDTH),
      .DMI_WIDTH(DMI_WIDTH),
      .STB_STATUS_WIDTH(STB_STATUS_WIDTH),
      .STB_DATA_WIDTH(STB_DATA_WIDTH)
      )
  read_intc
    (
     .CLK_I(CLK_I),
     .RST_NI(RST_NI),
     .READ_ADDRESS_I(tap_read_address),
     .READ_DATA_O(tap_read_data),
     .READ_VALID_O(tap_read_valid),
     .READ_READY_I(tap_read_ready),
     .VALID_ADDRESS_O(tap_valid_address),
     .DMI_READ_READY_O(dmi_read_ready),
     .DMI_READ_VALID_I(dmi_read_valid),
     .DMI_READ_DATA_I(dmi_read_data),
     .STB0_STATUS_READY_O(STB0_STATUS_READY_O),
     .STB0_STATUS_VALID_I(STB0_STATUS_VALID_I),
     .STB0_STATUS_I(STB0_STATUS_I),
     .STB0_DATA_READY_O(STB0_DATA_READY_O),
     .STB0_DATA_VALID_I(STB0_DATA_VALID_I),
     .STB0_DATA_I(STB0_DATA_I),
     .STB1_STATUS_READY_O(STB1_STATUS_READY_O),
     .STB1_STATUS_VALID_I(STB1_STATUS_VALID_I),
     .STB1_STATUS_I(STB1_STATUS_I),
     .STB1_DATA_READY_O(STB1_DATA_READY_O),
     .STB1_DATA_VALID_I(STB1_DATA_VALID_I),
     .STB1_DATA_I(STB1_DATA_I)
     ) ;

  logic                          dmi_write_ready;
  logic                          dmi_write_valid;
  logic [DMI_WIDTH-1:0]          dmi_write_data;
  TAP_WRITE_INTERCONNECT
    #(
      .WRITE_WIDTH(DMI_WIDTH),
      .DMI_WIDTH(DMI_WIDTH),
      .STB_CONTROL_WIDTH(STB_CONTROL_WIDTH),
      .STB_DATA_WIDTH(STB_DATA_WIDTH)
      )
  write_intc
    (
     .CLK_I(CLK_I),
     .RST_NI(RST_NI),
     .WRITE_ADDRESS_I(tap_write_address),
     .WRITE_DATA_I(tap_write_data),
     .WRITE_VALID_I(tap_write_valid),
     .WRITE_READY_O(tap_write_ready),
     .DMI_WRITE_READY_I(dmi_write_ready),
     .DMI_WRITE_VALID_O(dmi_write_valid),
     .DMI_WRITE_DATA_O(dmi_write_data),
     .STB0_CONTROL_READY_I(STB0_CONTROL_READY_I),
     .STB0_CONTROL_VALID_O(STB0_CONTROL_VALID_O),
     .STB0_CONTROL_O(STB0_CONTROL_O),
     .STB0_DATA_READY_I(STB0_DATA_READY_I),
     .STB0_DATA_VALID_O(STB0_DATA_VALID_O),
     .STB0_DATA_O(STB0_DATA_O),
     .STB1_CONTROL_READY_I(STB1_CONTROL_READY_I),
     .STB1_CONTROL_VALID_O(STB1_CONTROL_VALID_O),
     .STB1_CONTROL_O(STB1_CONTROL_O),
     .STB1_DATA_READY_I(STB1_DATA_READY_I),
     .STB1_DATA_VALID_O(STB1_DATA_VALID_O),
     .STB1_DATA_O(STB1_DATA_O)
     ) ;

  DMI_UART DMI_UART_1 (
                       .CLK_I              ( CLK_I            ),
                       .RST_NI             ( RST_NI           ),

                       .TAP_READ_READY_I   ( dmi_read_ready   ),
                       .TAP_READ_VALID_O   ( dmi_read_valid   ),
                       .TAP_READ_DATA_O    ( dmi_read_data    ),

                       .TAP_WRITE_READY_O  ( dmi_write_ready  ),
                       .TAP_WRITE_VALID_I  ( dmi_write_valid  ),
                       .TAP_WRITE_DATA_I   ( dmi_write_data   ),

                       .DMI_RESP_READY_O   ( DMI_RESP_READY_O ),
                       .DMI_RESP_VALID_I   ( DMI_RESP_VALID_I ),
                       .DMI_RESP_I         ( DMI_RESP_I       ),

                       .DMI_REQ_READY_I    ( DMI_REQ_READY_I  ),
                       .DMI_REQ_VALID_O    ( DMI_REQ_VALID_O  ),
                       .DMI_REQ_O          ( DMI_REQ_O        )
                       );

endmodule // Escape
