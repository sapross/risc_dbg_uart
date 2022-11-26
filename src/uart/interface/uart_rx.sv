//                              -*- Mode: SystemVerilog -*-
// Filename        : uart_rx.sv
// Description     : UART RX component with own sampling rate adjustment based on RX edges.
// Author          : Stephan Proß
// Created On      : Wed Nov 16 17:52:38 2022
// Last Modified By: Stephan Proß
// Last Modified On: Wed Nov 16 17:52:38 2022
// Update Count    : 0
// Status          : Unknown, Use with caution!

import baud_pkg::*;

module UART_RX #(
              parameter integer CLK_RATE = 100*10**6,
              parameter integer BAUD_RATE = 115200
)(
   input logic        CLK_I,
   input logic        RST_NI,
   output logic       RX_DONE_O,
   // output logic       RX_BRK_O,
   input logic        RX_I,
   output logic [7:0] DATA_O
) ;
  typedef enum        {st_idle, st_start, st_data, st_stop} state_t;
  state_t state, state_next;

  logic [2:0]         rx_buf;
  logic               rx, rx_prev;
  logic [7:0]         data, data_next;
  integer             nbit, nbit_next;
  logic               valid;
  logic               brk;

  assign DATA_O = data;
  assign RX_DONE_O = valid;
  // assign RX_BRK_O = brk;
  /* verilator lint_off WIDTH */
  localparam integer       OVERSAMPLING = ovsamp(CLK_RATE);
  localparam integer       BDDIVIDER = bddiv(CLK_RATE, BAUD_RATE);
  localparam integer       SAMPLE_INTERVAL = OVERSAMPLING * BDDIVIDER;


  logic               baudtick;
  bit [$clog2(SAMPLE_INTERVAL):0] baud_count, baud_interval;



  always_ff @(posedge CLK_I) begin : STABILIZE_RX
    if (!RST_NI) begin
      rx_buf <= '1;
      rx <= 1;
      rx_prev <= 1;
    end
    else begin
      rx_buf <= {RX_I, rx_buf[$size(rx_buf)-1:1]};
      rx <= rx_buf[0];
      rx_prev <= rx;
    end
  end // block: STABILIZE_RX

  always_ff @(posedge CLK_I) begin : CLOCK_RECOVERY
    if( !RST_NI || state == st_idle) begin
      baudtick <= 0;
      baud_count <= 0;
      baud_interval <= SAMPLE_INTERVAL/2 -1;
    end
    else begin
      if (baud_count < baud_interval) begin
        baud_count <= baud_count + 1;
        baudtick <= 0;
      end
      else begin
        baud_interval <= SAMPLE_INTERVAL - 1;
        baud_count <= 0;
        baudtick <= 1;
      end
      if( rx != rx_prev ) begin
        baud_interval <= baud_interval - (OVERSAMPLING*BDDIVIDER/2 - baud_count);
      end
    end // else: !if(!RST_NI | state == st_idle)
  end // block: CLOCK_RECOVERY


  always_ff @(posedge CLK_I) begin : FSM_CORE
    if (RST_NI==0) begin
      state <= st_idle;
      data <= '0;
      nbit <= 0;
    end
    else begin
      state <= state_next;
      data <= data_next;
      nbit <= nbit_next;
    end
  end

  always_comb begin : FSM
    state_next = state;
    data_next = data;
    nbit_next = nbit;
    valid = 0;
    brk = 0;
    case ( state )
      st_idle: begin
        if ( ~rx & rx_prev ) begin
          state_next = st_start;
        end
      end
      st_start : begin
        if ( baudtick ) begin
          state_next = st_data;
        end
      end
      st_data : begin
        if ( baudtick ) begin
          nbit_next = nbit + 1;
          data_next[nbit] = rx;
          if(nbit >= 7) begin
            nbit_next  = 0;
            state_next = st_stop;
          end
        end
      end
      st_stop : begin
        state_next = st_idle;
        valid = 1;
      end
    endcase; // case ( state )
  end
endmodule // UART_RX
