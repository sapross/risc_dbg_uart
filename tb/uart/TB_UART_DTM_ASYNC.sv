//                              -*- Mode: SystemVerilog -*-
// Filename        : TB_UART_DTM_ASYNC.sv
// Description     : Testbench for asynchronous TAP module.
// Author          : Stephan Proß
// Created On      : Wed Dec 14 11:33:16 2022
// Last Modified By: Stephan Proß
// Last Modified On: Wed Dec 14 11:33:16 2022
// Update Count    : 0
// Status          : Unknown, Use with caution!

import uart_pkg::*;
import dm::*;

// --------------------------------------------------------------------
// Testbench Module
// --------------------------------------------------------------------
module TB_UART_DTM_ASYNC (/*AUTOARG*/ ) ;

   localparam integer unsigned WIDTH = 41;
   // 40 ns
   localparam integer unsigned CLK_PERIOD = 40;
   // 1/3M ~ 333 ns
   localparam integer unsigned BAUD_PERIOD = 333;


   logic                       clk;
   logic                       reset_n;

   logic                       tx_write;
   logic [7:0]                 tx_data;
   logic                       tx_cmd_send;
   logic [7:0]                 tx_cmd;

   logic                       rx_read;
   logic [7:0]                 rx_data;
   logic                       rx_cmd;

   logic                       rx0, rx1;
   logic                       tx0,tx1;

   logic                       sw_channel;
   logic                       dmi_req_ready;
   logic                       dmi_req_valid;
   logic [40:0]                dmi_req_data;
   logic                       dmi_resp_ready;
   logic                       dmi_resp_valid;
   logic [33:0]                dmi_resp_data;
  assign dmi_resp_data = {dmi_req_data[31:0],2'h0};

   logic                       status_valid;
   logic [7:0]                 status;
   logic                       control_ready;
   logic                       stb_data_valid;
   logic [31:0]                stb_data;
   logic                       stb_data_ready;


   DTM_UART_Async
     #(
       .ESC(8'hB1),
       .CLK_RATE(25*10*6),
       .BAUD_RATE(3*10*6),
       .STB_CONTROL_WIDTH(8),
       .STB_STATUS_WIDTH(8),
       .STB_DATA_WIDTH(32)
       )
   DUT
     (
      .CLK_I(clk),
      .RST_NI(reset_n),
      .RX_I(rx0),
      .RX2_O(rx1),
      .TX_O(tx0),
      .TX2_I(tx1),
      .DMI_REQ_READY_I    (dmi_req_ready),
      .DMI_REQ_VALID_O    (dmi_req_valid),
      .DMI_REQ_O          (dmi_req_data),
      .DMI_RESP_READY_O   (dmi_resp_ready),
      .DMI_RESP_VALID_I   (dmi_resp_valid),
      .DMI_RESP_I         (dmi_resp_data),

      .STB0_STATUS_VALID_I(status_valid),
      .STB0_STATUS_I(status),
      .STB0_CONTROL_READY_I(control_ready),
      .STB0_DATA_VALID_I(stb_data_valid),
      .STB0_DATA_I(stb_data),
      .STB0_DATA_READY_I(stb_data_ready),
      .STB1_STATUS_VALID_I(status_valid),
      .STB1_STATUS_I(status),
      .STB1_CONTROL_READY_I(control_ready),
      .STB1_DATA_VALID_I(stb_data_valid),
      .STB1_DATA_I(stb_data),
      .STB1_DATA_READY_I(stb_data_ready)
      );


  initial begin
    clk = 0;
  end
  always begin
    #(CLK_PERIOD) clk = ~clk;
  end
  logic                        bclk;
  initial begin
    bclk = 0;
  end
  always begin
    #(BAUD_PERIOD) bclk = ~bclk;
  end


  initial begin
    reset_n = 0;

    rx0 = 1;
    rx1 = 1;
    tx0 = 1;
    tx1 = 1;
    sw_channel =0;
    dmi_req_ready = 1;
    dmi_resp_valid = 1;

    status_valid = 0;
    status = '0;
    control_ready = 0;
    stb_data_valid = 0;
    stb_data = '0;
    stb_data_ready = 0;

    #80 reset_n = 1;
  end

  // SetVALID_ADDRESS_I, control signals to default values and set reset signal.
  task reset_to_default;
     reset_n = 0;
     rx0 = 1;
     rx1 = 1;
     tx0 = 1;
     tx1 = 1;
     sw_channel =0;

     dmi_req_valid = 1;

     status_valid = 0;
     status = '0;
     control_ready = 0;
     stb_data_valid = 0;
     stb_data = '0;
     stb_data_ready = 0;
  endtask // reset_to_default

  task send_data;
    input logic [7:0] data;
    @(posedge bclk);
    rx0 = 0;
    @(posedge bclk);
    for(int i = 0; i<8; i++) begin
      rx0 = data[i];
      @(posedge bclk);
    end
    rx0 = 1;
    @(posedge bclk);
  endtask // send_data

  task test_read;
    $display("[ %0t ] Test: Read of valid addresses.", $time);
    reset_to_default();
    @(posedge clk);
    reset_n <= 1;

    send_data({8'hb1});
    send_data({CMD_RESET,ADDR_DMI});
    send_data(8'b11111110);
    send_data(8'b11111111);
    send_data(8'b11111111);
    send_data(8'b11111111);
    send_data(8'b01000011);
    send_data(8'b11111100);

    send_data({8'hb1});
    send_data({CMD_WRITE,ADDR_DMI});
    send_data(8'b00000001);
    send_data(8'b00000000);
    send_data(8'b00000000);
    send_data(8'b00000000);
    send_data(8'b01000000);
    send_data(8'b11111100);


    send_data({8'hb1});
    send_data({CMD_READ,ADDR_DMI});
    @(posedge clk);

  endtask // test_read

  initial begin
    #80
      test_read();
    $display("All tests done.");

    $dumpfile("TB_UART_TAP_ASYNC_DUMP.vcd");
    $dumpvars;
  end


endmodule // TB_UART_DTM_ASYNC
