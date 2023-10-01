//                              -*- Mode: Verilog -*-
// Filename        : TB_UART_TAP_ECHO.sv
// Description     : Testbench for asynchronous TAP module.
// Author          : Stephan Proß
// Created On      : Wed Dec 14 11:33:16 2022
// Last Modified By: Stephan Proß
// Last Modified On: Wed Dec 14 11:33:16 2022
// Update Count    : 0
// Status          : Unknown, Use with caution!

import uart_pkg::*;

// --------------------------------------------------------------------
// Testbench Module
// --------------------------------------------------------------------
module TB_UART_TAP_ECHO ();

  localparam integer unsigned WIDTH = 41;

  logic                clk;
  logic                reset_n;

  logic                read;
  logic [         7:0] data_rec;
  logic                rx_empty;
  logic                cmd_rec;

  logic                tx_ready;
  logic                write;

  logic [         7:0] data_send;
  logic                send_command;
  logic [         7:0] command;

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


  initial begin
    clk = 0;
  end
  always begin
    #5 clk = ~clk;
  end

  initial begin
    reset_n = 0;
    data_rec = '0;
    rx_empty = 1;
    cmd_rec = 0;
    dmi_error = '0;
    valid_address = '0;

    #20 reset_n = 1;
  end

  DMI_UART_TAP #(
      .WIDTH(WIDTH)
  ) DUT (
      .CLK_I (clk),
      .RST_NI(reset_n),

      .READ_O    (read),
      .DATA_REC_I(data_rec),
      .RX_EMPTY_I(rx_empty),
      .CMD_REC_I (cmd_rec),

      .TX_READY_I    (tx_ready),
      .WRITE_O       (write),
      .DATA_SEND_O   (data_send),
      .SEND_COMMAND_O(send_command),
      .COMMAND_O     (command),

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
  // Make tx_ready toggle if write is high.
  always_ff @(posedge clk) begin
    if (!reset_n) begin
      tx_ready <= 0;
    end else begin
      tx_ready <= 1;
      if (tx_ready && write) begin
        tx_ready <= 0;
      end
    end
  end

  logic new_data;
  always_ff @(posedge clk) begin
    if (!reset_n) begin
      new_data <= 0;
      read_valid <= 0;
      write_ready <= 0;
      read_data <= '0;
    end else begin
      write_ready <= 0;
      read_valid  <= 0;
      if (!new_data) begin
        write_ready <= 1;
        if (write_valid) begin
          read_data <= write_data;
          new_data  <= 1;
        end
      end else begin
        read_valid <= 1;
        if (read_ready) begin
          new_data <= 0;
        end
      end
    end
  end


  // SetVALID_ADDRESS_I, control signals to default values and set reset signal.
  task reset_to_default;
    reset_n = 0;
    data_rec = '0;
    rx_empty = 1;
    cmd_rec = 0;
    write_ready = 0;
    dmi_error = '0;
    valid_address = '0;
  endtask  // reset_to_default

  task test_echo;

    $display("[ %0t ] Test: Echo test", $time);
    reset_to_default();
    @(posedge clk);
    reset_n <= 1;
    @(posedge clk);
    $display("[ %0t ] Enable continuous read.", $time);
    rx_empty <= 0;
    cmd_rec  <= 1;
    data_rec <= {CMD_CONT_READ, ADDR_IDCODE};
    @(posedge clk);
    rx_empty <= 1;
    cmd_rec  <= 0;
    @(posedge clk);


    $display("[ %0t ] Begin writing.", $time);
    rx_empty <= 0;
    cmd_rec  <= 1;
    data_rec <= {CMD_WRITE, ADDR_IDCODE};
    while (!read) begin
      @(posedge clk);
    end
    @(posedge clk);
    cmd_rec  <= 0;
    rx_empty <= 0;
    @(posedge clk);
    for (int j = 0; j < 2; j++) begin
      for (int i = 1; i < 5; i++) begin
        rx_empty <= 0;
        data_rec <= i;
        @(posedge clk);
        while (!read) begin
          @(posedge clk);
        end
      end
    end

  endtask  // test_read

  initial begin
    #20 test_echo();
    $display("All tests done.");

    $dumpfile("TB_UART_TAP_ECHO_DUMP.vcd");
    $dumpvars;
  end


endmodule  // TB_UART_TAP_ECHO
