//                              -*- Mode: SystemVerilog -*-
// Filename        : uart_tx.sv
// Description     : TX module for uart interface.
// Author          : Stephan Proß
// Created On      : Wed Nov 16 16:09:23 2022
// Last Modified By: Stephan Proß
// Last Modified On: Wed Nov 16 16:09:23 2022
// Update Count    : 0
// Status          : Unknown, Use with caution!

import uart_pkg::*;


module UART_TX #(
                 parameter integer CLK_RATE = 100*10**6,
                 parameter integer BAUD_RATE = 115200,
                 parameter logic [7:0] RESUME =8'h00
                 ) (
                    input logic       CLK_I,
                    input logic       RST_NI,
                    input logic       TX_START_I,
                    output logic      TX_DONE_O,
                    output logic      TX_BUSY_O,
                    input logic       SEND_PAUSE_I,
                    input logic       ESC_DETECTED_I,
                    input logic       CHANNEL_I,
                    input logic       TX1_I,
                    output logic      TX0_O,
                    input logic [7:0] DATA_I
                    ) ;


  typedef enum                        logic {
                                             st_idle = 1'b0,
                                             st_send = 1'b1
                                             } state_t;
  state_t             state, state_next;
  assign TX_BUSY_O = state != st_idle;

  localparam integer unsigned SAMPLE_INTERVAL = CLK_RATE / BAUD_RATE;
  localparam integer unsigned REMAINDER_INTERVAL = ((CLK_RATE*10) / BAUD_RATE) / 10;
  bit [$clog2(SAMPLE_INTERVAL)-1:0] baud_count;
  bit [$clog2(REMAINDER_INTERVAL)-1:0] sample_count;

  logic               baudtick;
  logic               wait_cycle;

  logic               pausing, pausing_next;

  always_ff @(posedge CLK_I) begin : BAUD_GEN
    if( !RST_NI || state == st_idle) begin
      baudtick <= 0;
      wait_cycle <= 0;
      baud_count <= SAMPLE_INTERVAL -1;
      sample_count <= REMAINDER_INTERVAL-1;
    end
    else begin
      // Count down baud_count and set baud_tick for one turn at zero.
      // Each baud_tick sample_count is also decremented with
      // baud_tick and counter resets delayed by one cycle.
      // Purpose of the delay is to deal with phase deviations
      // introduced by integer division of frequencies.
      baudtick <= 0;
      if(!wait_cycle) begin
        if (baud_count > 0) begin
          baud_count <= baud_count - 1;
        end
        else begin
          if (sample_count > 0) begin
            baudtick <= 1;
            baud_count <= SAMPLE_INTERVAL - 1;
            sample_count <= sample_count - 1;
          end
          else begin
            wait_cycle <= 1;
          end
        end
      end
      else begin
        baudtick <= 1;
        wait_cycle <= 0;
        sample_count <= REMAINDER_INTERVAL - 1;
        baud_count <= SAMPLE_INTERVAL - 1;
      end
    end
  end // block: BAUD_GEN

  logic [9:0]                         frame,  frame_next; // UART Frame
  bit [$clog2(10)-1:0]                bitnum, bitnum_next; // Bit count
  logic                               tx, tx_next;
  logic                               last_esc, last_esc_next;

  assign TX0_O = (TX1_I && CHANNEL_I ) || (tx && !CHANNEL_I);

  always_ff @(posedge CLK_I) begin : FSM_CORE
    if (!RST_NI || CHANNEL_I) begin
      state <= st_idle;
      bitnum <= 0;
      frame <= 0;
      tx <= 1;
      pausing <= 0;
      last_esc <= 0;
    end
    else begin
      state <= state_next;
      bitnum <= bitnum_next;
      frame <= frame_next;
      tx <= tx_next;
      pausing <= pausing_next;
      last_esc <= last_esc_next;
    end // else: !if(!RST_NI)
  end // block: FSM_CORE

  always_comb begin : FSM

    state_next = state;
    bitnum_next = bitnum;
    frame_next = frame;
    tx_next = tx;
    TX_DONE_O = 0;
    pausing_next = pausing;
    last_esc_next <= last_esc;

    if (state == st_idle) begin

      tx_next = 1;
      if (SEND_PAUSE_I && !pausing) begin
        pausing_next = 1;
        // Avoid sending escape sequence if data send was escape seqeuence
        if (!last_esc) begin
          bitnum_next = 0;
          frame_next = {1'b1,ESC,1'b0};
          state_next = st_send;
        end
      end
      else if (!SEND_PAUSE_I && pausing) begin
        pausing_next = 0;
        // Simply resume sending if the last data send was escape.
        if (!last_esc) begin
          bitnum_next = 0;
          frame_next = {1'b1,RESUME,1'b0};
          state_next = st_send;
        end
      end
      else if (TX_START_I == 1) begin
        last_esc_next <= ESC_DETECTED_I;
        bitnum_next = 0;
        frame_next = {1'b1,DATA_I,1'b0};
        state_next = st_send;
      end

    end // if (state == st_idle)

    else if (state == st_send) begin
      // Multiplex message into TX
      tx_next = frame[bitnum];
      if (baudtick) begin
        if (bitnum == 9) begin
          state_next = st_idle;
          TX_DONE_O = 1;
        end
        else begin
          bitnum_next = bitnum  + 1;
        end
      end // if (baudtick)
    end // if (state == st_send)
  end // block: FSM

endmodule // UART_TX
