//                              -*- Mode: SystemVerilog -*-
// Filename        : uart_rx.sv
// Description     : UART RX component with own sampling rate adjustment based on RX edges.
// Author          : Stephan Proß
// Created On      : Wed Nov 16 17:52:38 2022
// Last Modified By: Stephan Proß
// Last Modified On: Wed Nov 16 17:52:38 2022
// Update Count    : 0
// Status          : Unknown, Use with caution!

module UART_RX #(
              parameter integer CLK_RATE = 100*10**6,
              parameter integer BAUD_RATE = 115200
)(
   input logic        CLK_I,
   input logic        RST_NI,
   output logic       RX_DONE_O,
   // output logic       RX_BRK_O,
   input logic        RX0_I,
   output logic       RX1_O,
   output logic [7:0] DATA_O,
   output logic       CHANNEL_O
) ;

  logic [2:0]         rx_buf;
  logic               rx, rx_prev;

  /* verilator lint_off WIDTH */
  always_ff @(posedge CLK_I) begin : STABILIZE_RX
    if (!RST_NI) begin
      rx_buf <= '1;
      rx <= 1;
      rx_prev <= 1;
    end
    else begin
      rx_buf <= {RX0_I, rx_buf[$size(rx_buf)-1:1]};
      rx <= rx_buf[0];
      rx_prev <= rx;
    end
  end // block: STABILIZE_RX


  localparam integer unsigned SAMPLE_INTERVAL = CLK_RATE / BAUD_RATE;
  localparam integer unsigned REMAINDER_INTERVAL = (CLK_RATE % BAUD_RATE)*10 / BAUD_RATE;
  bit [$clog2(SAMPLE_INTERVAL)-1:0] baud_count;
  bit [$clog2(REMAINDER_INTERVAL)-1:0] sample_count;

  logic               baudtick;
  logic               wait_cycle;

  logic               rx_edge_detected;


  always_ff @(posedge CLK_I) begin : BAUD_GEN
    if( !RST_NI || !rx_edge_detected) begin
      baudtick <= 0;
      wait_cycle <= 0;
      baud_count <= SAMPLE_INTERVAL/2 -1;
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

  logic [9:0] uart_frame;
  logic       rx_finished;
  bit [$clog2(10)-1:0] bit_count;
  logic              channel;
  assign CHANNEL_O = channel;
  always_ff @(posedge CLK_I) begin : CAPTURE_FRAME
    if (!RST_NI) begin
      uart_frame <= '1;
      rx_edge_detected <= 0;
      bit_count <= 9;
      RX_DONE_O <= 0;
      channel <= 0;
      rx_finished <= 0;
      DATA_O <= '0;
    end
    else begin
      RX_DONE_O <= 0;
      if(!rx_edge_detected) begin
          // Falling edge detected.
          if (rx_prev & ~rx) begin
            rx_edge_detected <= 1;
          end
      end
      else begin
        if (baudtick) begin
          uart_frame <= {rx, uart_frame[9:1]};
          if (bit_count > 0) begin
            bit_count <= bit_count -1;
          end
          else begin
            bit_count <= 9;
            rx_edge_detected <= 0;
            rx_finished <= 1;
          end
        end
      end
      if (rx_finished) begin
        // Is the received frame valid?
        rx_finished <= 0;
        if (!uart_frame[0] & uart_frame[9]) begin
          channel <= 0;
          DATA_O <= uart_frame[8:1];
          RX_DONE_O <= 1;
        end
        else begin
          channel <= 1;
        end
      end
    end
  end // block: CAPTURE_FRAME


  always_comb begin : RX_OUT
    if (!RST_NI) begin
      RX1_O = 0;
    end
    else begin
      if (channel) begin
        RX1_O = RX0_I;
      end
      else begin
        RX1_O = 0;
      end
    end
  end
endmodule // UART_RX
