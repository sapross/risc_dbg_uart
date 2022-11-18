//                              -*- Mode: SystemVerilog -*-
// Filename        : dtm_uart.sv
// Description     : Debug transport module consisting of the UART-Interface, the UART TAP and the Debug Module Interface.
// Author          : Stephan Proß
// Created On      : Fri Nov 18 11:41:27 2022
// Last Modified By: Stephan Proß
// Last Modified On: Fri Nov 18 11:41:27 2022
// Update Count    : 0
// Status          : Unknown, Use with caution!

module DTM_UART #(
                  parameter int CLK_RATE = 100000000,
                  parameter int BAUD_RATE = 3*10**6
                  )(
                    /*AUTOARG*/
                    input logic                         CLK_I,
                    input logic                         RST_NI,
                    input logic                         RX_I,
                    output logic                        TX_O,
                    output logic                        DMI_REQ_VALID_O,
                    input logic                         DMI_REQ_READY_I,
                    output logic [$bits(dmi_req_t)-1:0] DMI_REQ_O,
                    input logic                         DMI_RESP_VALID_I,
                    output logic                        DMI_RESP_READY_O,
                    input logic [$bits(dmi_resp_t)-1:0] DMI_RESP_I
                    ) ;

  // UART-Interface signals.
  logic                                                 rx_empty;
  logic                                                 rx_full;
  logic                                                 re, we;
  logic                                                 dsend;
  logic                                                 drec;
  logic                                                 tx_ready;

  // DMI specific signals
  logic                                                 dmi_hard_reset;
  logic                                                 dmi_read;
  logic                                                 dmi_write;
  logic                                                 dmi_done;
  logic [$bits(dmi_req_t)-1:0]                          dmi_dm;

  // TAP specific signals
  logic [$bits(dmi_req_t)-1:0]                          dmi_tap;
  logic                                                 dmi_reset;

  UART #(
         .CLK_RATE ( CLK_RATE  ),
         .BAUD_RATE( BAUD_RATE )
         ) UART_1 (
                   .CLK_I      ( CLK_I    ),
                   .RST_NI     ( RST_NI   ),
                   .RE_I       ( re       ),
                   .WE_I       ( we       ),
                   .RX_I       ( RX_I     ),
                   .TX_O       ( TX_O     ),
                   .RX_EMPTY_O ( rx_empty ),
                   .RX_FULL_O  ( rx_full  ),
                   .TX_READY_O ( tx_ready ),
                   .DSEND_I    ( dsend    ),
                   .DREC_O     ( drec     )
                   );


  DMI_UART_TAP #(
                 .CLK_RATE ( CLK_RATE  ),
                 .BAUD_RATE( BAUD_RATE )
                 ) DMI_UART_TAP_1 (
                                   .CLK_I            ( CLK_I          ),
                                   .RST_NI           ( RST_NI         ),
                                   .RE_O             ( re             ),
                                   .WE_O             ( we             ),
                                   .TX_READY_I       ( tx_ready       ),
                                   .RX_EMPTY_I       ( rx_empty       ),
                                   .DSEND_O          ( dsend          ),
                                   .DREC_I           ( drec           ),
                                   .DMI_HARD_RESET_O ( dmi_hard_reset ),
                                   .DMI_ERROR_I      ( 2'b00          ),
                                   .DMI_READ_O       ( dmi_read       ),
                                   .DMI_WRITE_O      ( dmi_write      ),
                                   .DMI_O            ( dmi_tap        ),
                                   .DMI_I            ( dmi_dm         ),
                                   .DMI_DONE_I       ( dmi_done       )
                                   );
  DMI_UART DMI_UART_1 (
                       .CLK_I            ( CLK_I            ),
                       .RST_NI           ( RST_NI           ),
                       .TAP_READ_I       ( dmi_read         ),
                       .TAP_WRITE_I      ( dmi_write        ),
                       .DMI_I            ( dmi_tap          ),
                       .DMI_O            ( dmi_dm           ),
                       .DONE_O           ( dmi_done         ),
                       .DMI_HARD_RESET_I ( dmi_hard_reset   ),

                       .DMI_RESP_VALID_I ( DMI_RESP_VALID_I ),
                       .DMI_RESP_READY_O ( DMI_RESP_READY_O ),
                       .DMI_RESP_I       ( DMI_RESP_I       ),

                       .DMI_REQ_VALID_O  ( DMI_REQ_VALID_O  ),
                       .DMI_REQ_READY_I  ( DMI_REQ_READY_I  ),
                       .DMI_REQ_O        ( DMI_REQ_O        ),

                       .DMI_RST_NO       ( dmi_reset        )
                       );

endmodule // DTM_UART
