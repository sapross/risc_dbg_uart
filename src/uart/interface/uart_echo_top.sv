
import uart_pkg::*;

module uart_echo_top #(
    int UART_CLK_RATE  = 50 * 10 ** 6,
    int UART_BAUD_RATE = 3 * 10 ** 6
) (
    input logic clk_i,
    input logic rst_i,

    input  logic debug_rx,
    output logic debug_tx,

    output logic led0

);
  logic sys_clk;
  logic rst_n;
  assign rst_n = !rst_i;
  assign led0  = rst_n;

  clk_wiz_0 i_clk_wiz_0 (
      // Clock out ports
      .clk_out1(sys_clk),
      // Status and control signals
      .reset(rst_i),
      .locked(),
      // Clock in ports
      .clk_in1(clk_i)
  );

  logic write;
  logic read;
  logic [7:0] data;

  logic ready, empty, full;

  // Debug
  UART #(
      .CLK_RATE (UART_CLK_RATE),
      .BAUD_RATE(UART_BAUD_RATE)
  ) uart_i (
      .CLK_I (sys_clk),
      .RST_NI(rst_n),

      .WE_I(ready & !empty),
      .DSEND_I(data),
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



endmodule
