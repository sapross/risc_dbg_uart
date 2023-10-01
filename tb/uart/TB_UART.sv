//                              -*- Mode: SystemVerilog -*-
// Filename        : TB_UART.sv
// Description     : Testbench for UART interface.
// Author          : Stephan Proß
// Created On      : Wed Dec 14 11:33:16 2022
// Last Modified By: Stephan Proß
// Last Modified On: Wed Dec 14 11:33:16 2022
// Update Count    : 0
// Status          : Unknown, Use with caution!

import uart_pkg::*;

module TB_UART ();

  localparam integer unsigned CLK_RATE = 100 * 10 ** 6;
  localparam integer unsigned CLK_PERIOD = 10;

  localparam integer unsigned BAUD_RATE = 3 * 10 ** 6;
  localparam integer unsigned BAUD_PERIOD = 333;

  localparam integer unsigned CLK_BAUD_RATIO = CLK_RATE / BAUD_RATE;


  logic clk_i;
  initial begin
    clk_i = 0;
  end
  always begin
    #(CLK_PERIOD) clk_i = ~clk_i;
  end

  logic rst_i;

  initial begin
    rst_i = 1;
    #(3 * CLK_PERIOD) rst_i = 0;
  end

  logic debug_rx;
  assign debug_rx = 1;

  logic debug_tx;
  logic led0;

  logic sys_clk;
  logic rst_n;

  assign rst_n = !rst_i;
  assign led0  = rst_n;


  logic write;
  logic read;
  logic [7:0] data;

  logic ready, empty, full;

  // Debug
  (* dont_touch = "yes" *)
  UART #(
      .CLK_RATE (CLK_RATE),
      .BAUD_RATE(BAUD_RATE)
  ) uart_i (
      .CLK_I (clk_i),
      .RST_NI(rst_n),

      .WE_I(ready),
      .DSEND_I(8'hFF),
      .ESC_DETECTED_I(1'b0),

      .RE_I  (!empty),
      .DREC_O(data),

      .RX0_I(debug_rx),
      .RX1_O(),
      .TX0_O(debug_tx),
      .TX1_I(1'b1),

      .TX_READY_O(ready),
      .RX_EMPTY_O(empty),
      .RX_FULL_O (full),

      .SW_CHANNEL_I(1'b0),
      .CHANNEL_O()
  );

  sequence uart_frame_hFF;
    !debug_tx [* CLK_BAUD_RATIO +1] ##1 debug_tx [* CLK_BAUD_RATIO * 8] ##1 debug_tx[* CLK_BAUD_RATIO];
  endsequence : uart_frame_hFF
  // Assert that a reset causes the correct values visible at the outputs.
  property find_transmission_of_hFF;
    @(posedge clk_i) disable iff (rst_i) $fell(
        debug_tx
    ) |-> uart_frame_hFF;
  endproperty  // find_transmission_of_hFF
  assert property (find_transmission_of_hFF)
  else $error("%m Found frame which did not resolve to hFF!");

endmodule
