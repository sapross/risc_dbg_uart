//                              -*- Mode: Verilog -*-
// Filename        : rx_escape.sv
// Description     : Catches escape sequences in rx stream and notifies TAP that the next symbol is to be categorized as control.
// Author          : Stephan Proß
// Created On      : Sun Jan  8 11:29:32 2023
// Last Modified By: Stephan Proß
// Last Modified On: Sun Jan  8 11:29:32 2023
// Update Count    : 0
// Status          : Unknown, Use with caution!


module RX_Escape
  #(
    parameter logic [7:0] ESC = 8'hB1
    )
  (
   input logic        CLK_I,
   input logic        RST_NI,
   // Signals from/to UART-RX
   input logic [7:0]  DATA_REC_I,
   input logic        RX_EMPTY_I,
   output logic       READ_O,
   // Signals from/to TAP
   input logic        READ_I,
   output logic       RX_EMPTY_O,
   output logic       COMMAND_O,
   output logic [7:0] DATA_REC_O
   );

  typedef enum
              {
               st_idle,
               st_data,
               st_escape,
               st_command
               } state_t;
  state_t state, state_next;

  logic [7:0]         data, data_next;
  assign DATA_REC_O = data;

  always_ff @(posedge CLK_I) begin : FSM_CORE
    if(!RST_NI) begin
      state <= st_idle;
      data <= '0;
    end
    else begin
      state <= state_next;
      data <= data_next;
    end
  end

  always_comb begin: FSM
    if (!RST_NI) begin
      state_next = st_idle;
      data_next = '0;
      COMMAND_O = 0;
      RX_EMPTY_O = 1;
      READ_O = 0;
    end
    else begin
      state_next = state;
      data_next = data;
      COMMAND_O = 0;
      RX_EMPTY_O = 1;
      READ_O = 0;
      case (state)
        st_idle : begin
          if(!RX_EMPTY_I) begin
            READ_O = 1;
            data_next = DATA_REC_I;

            if (DATA_REC_I == ESC) begin
              state_next = st_escape;
            end
            else begin
              state_next = st_data;
            end
          end
        end
        st_data : begin
          RX_EMPTY_O = 0;
          if (READ_I) begin
            state_next = st_idle;
          end
        end
        st_escape : begin
          if(!RX_EMPTY_I) begin
            READ_O = 1;
            data_next = DATA_REC_I;
            state_next = st_command;
          end
        end
        st_command : begin
          COMMAND_O = 1;
          RX_EMPTY_O = 0;
          if (READ_I) begin
            state_next = st_idle;
          end
        end
      endcase // case (state)
    end
  end

  


endmodule // RX_Escape
