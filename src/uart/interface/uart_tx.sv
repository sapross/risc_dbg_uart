//                              -*- Mode: SystemVerilog -*-
// Filename        : uart_tx.sv
// Description     : TX module for uart interface.
// Author          : Stephan Proß
// Created On      : Wed Nov 16 16:09:23 2022
// Last Modified By: Stephan Proß
// Last Modified On: Wed Nov 16 16:09:23 2022
// Update Count    : 0
// Status          : Unknown, Use with caution!


module UART_TX #(
                 parameter integer OVERSAMPLING = 16,
                 parameter integer BDDIVIDER = 27
                 ) (
                    input logic       CLK_I,
                    input logic       RST_NI,
                    input logic       TX_START_I,
                    output logic      TX_DONE_O,
                    output logic      TX_O,
                    input logic [7:0] DATA_I

                    ) ;
  typedef enum                        logic {
                                             st_idle = 1'b0,
                                             st_send = 1'b1
                                             } state_t;
  state_t             state, state_next;

  integer                             btick_cnt, btick_cnt_next; // Number of baud ticks.
  integer                             bitnum, bitnum_next; // Bit count
  logic [9:0]                         frame,  frame_next; // UART Frame
  logic                               tx, tx_next;
  assign TX_O = tx;

  logic                               baudtick;
  integer                             baud_count;

  always_ff @(posedge CLK_I) begin : BAUDGEN
    baudtick <= 0;
    if (~RST_NI) begin
      baud_count <= 0;
    end
    else begin
      if ( baud_count < BDDIVIDER - 1 ) begin
        baud_count <= baud_count + 1;
      end
      else begin
        baud_count <= 0;
        baudtick <= 1;
      end
    end // else: !if(~RST_NI)
  end // block: BAUDGEN

  always_ff @(posedge CLK_I) begin : FSM_CORE
    if (~RST_NI) begin
      state <= st_idle;
      btick_cnt <= 0;
      bitnum <= 0;
      frame <= 0;
      tx <= 1;
    end
    else begin
      state <= state_next;
      btick_cnt <= btick_cnt_next;
      bitnum <= bitnum_next;
      frame <= frame_next;
      tx <= tx_next;
    end // else: !if(~RST_NI)
  end // block: FSM_CORE

  always_comb begin : FSM
    state_next = state;
    btick_cnt_next = btick_cnt;
    bitnum_next = bitnum;
    frame_next = frame;
    tx_next = tx;
    TX_DONE_O = 0;

    if (state == st_idle) begin

      tx_next <= 1;
      if (TX_START_I == 1) begin
        btick_cnt_next <= 0;
        bitnum_next <= 0;
        frame_next <= {1,DATA_I,0};
      end

    end // if (state == st_idle)

    else if (state == st_send) begin
      // Multiplex message into TX
      tx_next <= frame[bitnum];

      if (B_TICK_I) begin
        if (btick_cnt == OVERSAMPLING -1) begin
          btick_cnt_next <= 0;
          if (bitnum == 9) begin
            state_next <= st_idle;
            TX_DONE_O <= 1;
          end
          else begin
            bitnum_next <= bitnum  + 1;
          end
        end // if (btick_cnt == OVERSAMPLING -1)
        else begin
          btick_cnt_next <= btick_cnt + 1;
        end // else: !if(btick_cnt == OVERSAMPLING -1)
      end // if (B_TICK_I)
    end // if (state == st_send)
  end // block: FSM

endmodule // UART_TX
