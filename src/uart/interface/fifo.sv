//                              -*- Mode: Verilog -*-
// Filename        : fifo.sv
// Description     : Simple FIFO.
// Author          : Stephan Proß
// Created On      : Wed Nov 16 15:21:46 2022
// Last Modified By: Stephan Proß
// Last Modified On: Wed Nov 16 15:21:46 2022
// Update Count    : 0
// Status          : Unknown, Use with caution!
module SIMPLE_FIFO #(
parameter integer ABITS = 4,
parameter integer DBITS = 8
)(
  input logic CLK_I,
  input logic RST_NI,
  input logic RE_I,
  input logic WE_I,
  input logic [7:0] W_DATA_I,
  output logic [7:0] R_DATA_O,
  output logic FULL_O,
  output logic EMPTY_O
);
  typedef logic [DBITS-1:0] dtype;
  typedef logic [ABITS-1:0] atype;
  dtype [2**ABITS-1:0] ram = '{ default: '0};

  typedef bit [ABITS-1:0]   ptype;

  ptype      w_ptr;
  ptype      w_ptr_next;
  ptype      w_ptr_inc;

  ptype      r_ptr;
  ptype      r_ptr_next;
  ptype      r_ptr_inc;

  logic        full, full_next;
  logic        empty, empty_next;
  logic        w_en;

  assign w_en = WE_I & ~full;
  assign FULL_O = full;
  assign EMPTY_O = empty;

  always_ff @(posedge CLK_I) begin : PROC_WRITE
    if(w_en) begin
      ram[w_ptr % 2**ABITS] <= W_DATA_I;
    end
  end

  always_comb begin : PROC_READ
    R_DATA_O = ram[r_ptr % 2**ABITS];
  end

  always_ff @(posedge CLK_I) begin : FSM_CORE
    if (!RST_NI) begin
      w_ptr <= 0;
      r_ptr <= 0;
      full <= 0;
      empty <= 1;
    end else begin
      w_ptr <= w_ptr_next;
      r_ptr <= r_ptr_next;
      full <= full_next;
      empty <= empty_next;
    end // else: !if!RST_NI
  end // block: FSM_CORE

  always_comb begin : FSM
    w_ptr_inc = (w_ptr + 1 ) %  2 ** ABITS;
    r_ptr_inc = (r_ptr + 1 ) %  2 ** ABITS;

    w_ptr_next = w_ptr;
    r_ptr_next = r_ptr;

    full_next  = full;
    empty_next = empty;

    if (~w_en & RE_I) begin

      if (!empty) begin
        r_ptr_next = r_ptr_inc;
        full_next = 0;
        if (r_ptr_inc == w_ptr) begin
          empty_next = 1;
        end
      end

    end
    else if (w_en & ~RE_I) begin

      if (!full) begin
        w_ptr_next = w_ptr_inc;
        empty_next = 0;
        if (w_ptr_inc == r_ptr) begin
          full_next = 1;
        end
      end

    end
    else if (w_en & RE_I) begin

      w_ptr_next = w_ptr_inc;
      r_ptr_next = r_ptr_inc;

    end
  end // block: FSM

endmodule // FIFO
