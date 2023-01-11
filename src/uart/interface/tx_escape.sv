//                              -*- Mode: Verilog -*-
// Filename        : tx_escape.sv
// Description     : Catches escape sequences in tx stream and escapes on command.
// Author          : Stephan Proß
// Created On      : Sun Jan  8 11:29:32 2023
// Last Modified By: Stephan Proß
// Last Modified On: Sun Jan  8 11:29:32 2023
// Update Count    : 0
// Status          : Unknown, Use with caution!


module TX_Escape
  #(
    parameter logic [7:0] ESC = 8'hB1
    )
  (
   input logic        CLK_I,
   input logic        RST_NI,
   // Signals from/to UART-TX
   input logic        TX_READY_I,
   output logic [7:0] DATA_SEND_O,
   output logic       WRITE_O,
   // Signals from/to TAP
   output logic       TX_READY_O,
   input logic [7:0]  DATA_SEND_I,
   input logic        WRITE_I,
   input logic        WRITE_COMMAND_I,
   input logic  [7:0] COMMAND_I
   );


  logic [7:0]         data_buffer;
  logic               send_esc;
  logic               send_data ;


  always_ff @(posedge CLK_I) begin
    if (!RST_NI) begin
      send_esc <= 0;
      send_data <= 0;
      data_buffer <= '0;
      TX_READY_O <= TX_READY_I;
    end
    else begin
      // Check if write data from tap needs to be
      // escaped or is explicitly a command.
      if (WRITE_COMMAND_I) begin
        data_buffer <= COMMAND_I;
        send_data <= 1;
        send_esc <= 1;
        TX_READY_O <= 0;
      end
      else if (WRITE_I) begin
        data_buffer <= DATA_SEND_I;
        send_data <= 1;
        if (DATA_SEND_I == ESC ) begin
          TX_READY_O <= 0;
          send_esc <= 1;
        end
        else begin
          TX_READY_O <= TX_READY_I;
          send_esc <= 0;
        end
      end
      // When TX is ready, lower first send_esc
      // as the escape-sequence is transmitted before
      // data.
      if (TX_READY_I) begin
        if (send_esc) begin
          send_esc <= 0;
        end
        else begin
          if (send_data) begin
            send_data <= 0;
          end
        end
      end

    end // else: !if(!RST_NI)
  end // always_ff @ (posedge CLK_I)

  always_comb begin
    if (RST_NI) begin
      DATA_SEND_O = '0;
      WRITE_O = 0;
    end
    else begin
      if (send_esc) begin
        WRITE_O = 1;
        DATA_SEND_O = ESC;
      end
      else if (send_data) begin
        WRITE_O = 1;
        DATA_SEND_O = data_buffer;
      end
      else begin
        WRITE_O = 0;
        DATA_SEND_O = '0;
      end
    end
  end

endmodule // TX_Escape
