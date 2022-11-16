//                              -*- Mode: SystemVerilog -*-
// Filename        : uart.sv
// Description     : UART Interface top module.
// Author          : Stephan Proß
// Created On      : Wed Nov 16 18:28:11 2022
// Last Modified By: Stephan Proß
// Last Modified On: Wed Nov 16 18:28:11 2022
// Update Count    : 0
// Status          : Unknown, Use with caution!

// import baud_pkg::*;

module UART #(
              parameter integer CLK_RATE = 100*10**6,
              parameter integer BAUD_RATE = 115200
) (
   input logic        CLK_I,
   input logic        RST_NI,
   input logic        RE_I,
   input logic        WE_I,
   input logic        RX_I,
   output logic       TX_O,
   output logic       TX_READY_O,
   output logic       RX_EMPTY_O,
   output logic       RX_FULL_O,
   input logic [7:0]  DSEND_I,
   output logic [7:0] DREC_O
) ;

  logic               baudtick;
  logic               tx_start;
  logic               rx_rd, rx_wr;
  logic               tx_rd, tx_wr;
  logic [7:0]         rx_din, rx_dout;
  logic [7:0]         tx_din, tx_dout;
  logic               tx_full;
  logic               tx_empty;

  assign tx_start = ~tx_empty;
  assign TX_READY_O = ~tx_full;

 // RX half of the interface
  UART_RX #(
            .OVERSAMPLING ( ovsamp(CLK_RATE)           ),
            .BDDIVIDER    ( bddiv(CLK_RATE, BAUD_RATE) )
            ) uart_rx_i
    (/*AUTOINST*/
     .CLK_I     ( CLK_I  ),
     .RST_NI    ( RST_NI ),
     .RX_DONE_O ( rx_wr  ),
     .RX        ( RX_I   ),
     .DATA_O    ( rx_din )
     );

  FIFO FIFO_RX ( /*AUTOINST*/
            .CLK_I    ( CLK_I      ),
            .RST_NI   ( RST_NI     ),
            .RE_I     ( tx_rd      ),
            .WE_I     ( tx_wr      ),
            .W_DATA_I ( rx_din     ),
            .R_DATA_O ( rx_dout    ),
            .FULL_O   ( RX_EMPTY_O ),
            .EMPTY_O  ( RX_FULL_O  )
             );

 // TX half of the interface
  UART_TX #(
            .OVERSAMPLING ( ovsamp(CLK_RATE) )
            ) uart_tx_i
    (/*AUTOINST*/
     .CLK_I      ( CLK_I    ),
     .RST_NI     ( RST_NI   ),
     .TX_START_I ( tx_start ),
     .TX_DONE_O  ( tx_rd    ),
     .TX         ( TX_O     ),
     .DATA_I     ( tx_dout  )
     );

  FIFO FIFO_TX ( /*AUTOINST*/
            .CLK_I    ( CLK_I    ),
            .RST_NI   ( RST_NI   ),
            .RE_I     ( tx_rd    ),
            .WE_I     ( WE_I     ),
            .W_DATA_I ( DSEND_I  ),
            .R_DATA_O ( rx_dout  ),
            .FULL_O   ( tx_full  ),
            .EMPTY_O  ( tx_empty )
             );

  always_ff @(posedge CLK_I) begin : WRITE
    if (~RST_NI) begin
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
