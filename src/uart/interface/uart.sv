//                              -*- Mode: SystemVerilog -*-
// Filename        : uart.sv
// Description     : UART Interface top module.
// Author          : Stephan Proß
// Created On      : Wed Nov 16 18:28:11 2022
// Last Modified By: Stephan Proß
// Last Modified On: Wed Nov 16 18:28:11 2022
// Update Count    : 0
// Status          : Unknown, Use with caution!


module UART #(
              parameter integer CLK_RATE = 100*10**6,
              parameter integer BAUD_RATE = 115200
) (
   input logic        CLK_I,
   input logic        RST_NI,

   input logic        WE_I,
   input logic [7:0]  DSEND_I,

   input logic        RE_I,
   output logic [7:0] DREC_O,

   input logic        RX_I,
   output logic       RX2_O,
   output logic       TX_O,
   input logic        TX2_I,
   output logic       TX_READY_O,
   output logic       RX_EMPTY_O,
   output logic       RX_FULL_O,

   input logic        SW_CHANNEL_I,
   output logic       CHANNEL_O
);

  logic               tx_start;
  logic               rx_rd, rx_wr;
  logic               tx_rd, tx_wr;
  logic [7:0]         rx_din, rx_dout;
  logic [7:0]         tx_dout;
  logic               tx_full;
  logic               tx_empty;

  logic               channel;
  logic               rx_channel;
  logic               switch_channel;
  logic               send_pause;
  logic               rx_full;
  logic               rx_half_full;

  assign RX_FULL_O= rx_full;


  assign switch_channel = SW_CHANNEL_I;
  assign tx_start = WE_I;
  assign TX_READY_O = ~tx_busy;
  assign CHANNEL_O = channel;

 // RX half of the interface
  UART_RX #(
            .CLK_RATE  ( CLK_RATE  ),
            .BAUD_RATE ( BAUD_RATE )
            ) UART_RX_I
    (/*AUTOINST*/
     .CLK_I     ( CLK_I  ),
     .RST_NI    ( RST_NI ),
     .RX_DONE_O ( rx_wr  ),
     .RX_I      ( RX_I   ),
     .RX2_O     ( RX2_O  ),
     .DATA_O    ( rx_din ),
     .CHANNEL_O ( rx_channel)
     );

  SIMPLE_FIFO FIFO_RX ( /*AUTOINST*/
            .CLK_I        ( CLK_I      ),
            .RST_NI       ( RST_NI     ),
            .RE_I         ( rx_rd      ),
            .WE_I         ( rx_wr      ),
            .W_DATA_I     ( rx_din     ),
            .R_DATA_O     ( rx_dout    ),
            .FULL_O       ( rx_full    ),
            .HALF_FULL_O  ( rx_half_full    ),
            .EMPTY_O      ( RX_EMPTY_O )
             );

 // TX half of the interface
  UART_TX #(
            .CLK_RATE  ( CLK_RATE  ),
            .BAUD_RATE ( BAUD_RATE )
            ) UART_TX_I
    (/*AUTOINST*/
     .CLK_I        ( CLK_I        ),
     .RST_NI       ( RST_NI       ),
     .TX_START_I   ( WE_I         ),
     .TX_DONE_O    (              ),
     .TX_BUSY_O    ( tx_busy      ),
     .TX2_I        ( TX2_I        ),
     .TX_O         ( TX_O         ),
     .DATA_I       ( DSEND_I      ),
     .SEND_PAUSE_I ( rx_half_full ),
     .CHANNEL_I    ( channel      )
     );


  always_ff @(posedge CLK_I) begin : CHANGE_CHANNEL
    if (!RST_NI) begin
      channel <= 0;
    end
    else begin
      if (rx_channel || switch_channel && !channel) begin
        channel <= 1;
      end
      else begin
        channel <= 0;
      end
    end
  end


  always_ff @(posedge CLK_I) begin : WRITE
    if (!RST_NI) begin
      tx_wr <= 0;
    end
    else begin
      tx_wr <= WE_I;
    end
  end

  always_comb begin : READ
    rx_rd = RE_I;

    DREC_O = '0;
    if (RE_I) begin
      DREC_O = rx_dout;
    end
  end

endmodule // UART
