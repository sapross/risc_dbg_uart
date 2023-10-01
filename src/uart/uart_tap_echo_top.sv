

import uart_pkg::*;
module uart_tap_echo_top #(
    int UART_DBG_CLK_RATE  = 50 * 10 ** 6,
    int UART_DBG_BAUD_RATE = 3 * 10 ** 6
) (
    input logic clk_i,
    input logic rst_i,

    input  logic debug_rx,
    output logic debug_tx,

    output logic led0

);
  logic sys_clk;
  assign led0 = !rst_i;

  clk_wiz_0 i_clk_wiz_0 (
      // Clock out ports
      .clk_out1(sys_clk),
      // Status and control signals
      .reset(0),
      .locked(),
      // Clock in ports
      .clk_in1(clk_i)
  );

  // ---------------
  // UART INTERFACE
  // ---------------
  logic       tx_write;
  logic [7:0] tx_data;
  logic       uintf_ready;

  logic       rx_read;
  logic [7:0] rx_data;
  logic       esc_detected;
  logic       uintf_empty;
  logic       uintf_full;

  logic       sw_channel;
  logic       channel;

  UART #(
      .CLK_RATE (UART_DBG_CLK_RATE),
      .BAUD_RATE(UART_DBG_BAUD_RATE)
  ) uart_1 (
      .CLK_I         (sys_clk),
      .RST_NI        (!rst_i),
      .WE_I          (tx_write),
      .DSEND_I       (tx_data),
      .RE_I          (rx_read),
      .DREC_O        (rx_data),
      .ESC_DETECTED_I(esc_detected),
      .RX0_I         (debug_rx),
      .RX1_O         (),
      .TX0_O         (debug_tx),
      .TX1_I         (1'b1),
      .TX_READY_O    (uintf_ready),
      .RX_EMPTY_O    (uintf_empty),
      .RX_FULL_O     (uintf_full),
      .SW_CHANNEL_I  (1'b0),
      .CHANNEL_O     (channel)
  );

  // ---------------
  // UART INTERFACE ESCAPE
  // ---------------

  logic       tap_rx_read;
  logic [7:0] tap_rx_data;
  logic       tap_rx_cmd;
  logic       tap_rx_empty;

  logic       tap_tx_write;
  logic [7:0] tap_tx_data;
  logic       tap_tx_cmd_write;
  logic [7:0] tap_tx_cmd;
  logic       tap_tx_ready;
  (* DONT_TOUCH = "true" *)
  RX_Escape #(
      .ESC(ESC)
  ) rx_esc (
      .CLK_I (sys_clk),
      .RST_NI(!rst_i),

      .DATA_REC_I(rx_data),
      .RX_EMPTY_I(uintf_empty),
      .READ_O    (rx_read),

      .READ_I    (tap_rx_read),
      .RX_EMPTY_O(tap_rx_empty),
      .COMMAND_O (tap_rx_cmd),
      .DATA_REC_O(tap_rx_data)
  );


  (* DONT_TOUCH = "true" *)
  TX_Escape #(
      .ESC(ESC)
  ) tx_esc (
      .CLK_I (sys_clk),
      .RST_NI(!rst_i),

      .TX_READY_I    (uintf_ready && !channel),
      .DATA_SEND_O   (tx_data),
      .WRITE_O       (tx_write),
      .ESC_DETECTED_O(esc_detected),

      .TX_READY_O     (tap_tx_ready),
      .DATA_SEND_I    (tap_tx_data),
      .WRITE_I        (tap_tx_write),
      .WRITE_COMMAND_I(tap_tx_cmd_write),
      .COMMAND_I      (tap_tx_cmd)

  );

  // // ---------------
  // // UART TAP
  // // ---------------
  localparam integer WIDTH = get_write_length(ADDR_DMI);

  logic [IRLENGTH-1:0] write_address;

  logic [   WIDTH-1:0] write_data;
  logic                write_valid;
  logic                write_ready;

  logic                dmi_hard_reset;
  logic [         1:0] dmi_error;

  logic                read_valid;
  logic                read_ready;
  logic [IRLENGTH-1:0] read_address;
  logic [   WIDTH-1:0] read_data;
  logic [IRLENGTH-1:0] valid_address;
  DMI_UART_TAP #(
      .WIDTH(WIDTH)
  ) DUT (
      .CLK_I (sys_clk),
      .RST_NI(!rst_i),

      .READ_O    (tap_rx_read),
      .DATA_REC_I(tap_rx_data),
      .RX_EMPTY_I(tap_rx_empty),
      .CMD_REC_I (tap_rx_cmd),

      .TX_READY_I    (tap_tx_ready),
      .WRITE_O       (tap_tx_write),
      .DATA_SEND_O   (tap_tx_data),
      .SEND_COMMAND_O(tap_tx_cmd_write),
      .COMMAND_O     (tap_tx_cmd),

      .DMI_HARD_RESET_O(dmi_hard_reset),
      .DMI_ERROR_I     (dmi_error),

      .WRITE_ADDRESS_O(write_address),
      .WRITE_DATA_O   (write_data),
      .WRITE_VALID_O  (write_valid),
      .WRITE_READY_I  (write_ready),

      .READ_ADDRESS_O (read_address),
      .READ_DATA_I    (read_data),
      .READ_VALID_I   (read_valid),
      .READ_READY_O   (read_ready),
      .VALID_ADDRESS_I(valid_address)
  );

  logic new_data;
  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      new_data <= 0;
      read_valid <= 0;
      write_ready <= 0;
      read_data <= '0;
    end else begin
      write_ready <= 0;
      read_valid  <= 0;
      if (!new_data) begin
        write_ready <= 1;
        if (write_valid && write_ready) begin
          read_data <= write_data;
          new_data  <= 1;
        end
      end else begin
        read_valid <= 1;
        if (read_ready && read_valid) begin
          new_data <= 0;
        end
      end
    end
  end



endmodule
// Local Variables:
// verilog-library-flags:("-f ../../include.vc")
// End:
