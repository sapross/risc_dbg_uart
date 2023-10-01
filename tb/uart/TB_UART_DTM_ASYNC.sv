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


   logic                       rx0, rx1;
   logic                       tx0,tx1;

   logic                       sw_channel;
   logic                       dmi_req_ready;
   logic                       dmi_req_valid;
   logic [40:0]                dmi_req_data;
   logic                       dmi_resp_ready;
   logic                       dmi_resp_valid;
   logic [33:0]                dmi_resp_data;

   logic                       status_valid;
   logic [7:0]                 status;
   logic                       control_ready;
   logic                       stb_data_valid;
   logic [31:0]                stb_data;
   logic                       stb_data_ready;


   DTM_UART
     #(
       .ESC(ESC),
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
      .RX0_I(rx0),
      .RX1_O(rx1),
      .TX0_O(tx0),
      .TX1_I(tx1),
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

  logic                        dm_slave_req;
  logic                        dm_slave_we;
  logic [64-1:0]               dm_slave_addr;
  logic [64/8-1:0]             dm_slave_be;
  logic [64-1:0]               dm_slave_wdata;
  logic [64-1:0]               dm_slave_rdata;

  logic                        dm_master_req;
  logic [64-1:0]               dm_master_add;
  logic                        dm_master_we;
  logic [64-1:0]               dm_master_wdata;
  logic [64/8-1:0]             dm_master_be;
  logic                        dm_master_gnt;
  logic                        dm_master_r_valid;
  logic [64-1:0]               dm_master_r_rdata;
  logic                        ndmreset;
  logic                        dmactive;
  logic                        debug_req_irq;

  localparam                   dm::hartinfo_t DebugHartInfo = '{
                                                                zero1:        '0,
                                                                nscratch:      2, // Debug module needs at least two scratch regs
                                                                zero0:        '0,
                                                                dataaccess: 1'b1, // data registers are memory mapped in the debugger
                                                                datasize: dm::DataCount,
                                                                dataaddr: dm::DataAddr
                                              };
  dm_top #(
           .NrHarts          ( 1                 ),
           .BusWidth         ( 64                ),
           .SelectableHarts  ( 1'b1              )
           ) i_dm_top (
                       .clk_i            ( clk               ),
                       .rst_ni           ( reset_n            ), // PoR
                       .testmode_i       ( 1'b0              ),
                       .ndmreset_o       ( ndmreset          ),
                       .dmactive_o       ( dmactive          ), // active debug session
                       .debug_req_o      ( debug_req_irq     ),
                       .unavailable_i    ( '0                ),
                       .hartinfo_i       ( {DebugHartInfo} ),
                       .slave_req_i      ( '0                ),
                       .slave_we_i       ( '0                ),
                       .slave_addr_i     ( '0                ),
                       .slave_be_i       ( '0                ),
                       .slave_wdata_i    ( '0                ),
                       .slave_rdata_o    ( dm_slave_rdata    ),
                       .master_req_o     ( dm_master_req     ),
                       .master_add_o     ( dm_master_add     ),
                       .master_we_o      ( dm_master_we      ),
                       .master_wdata_o   ( dm_master_wdata   ),
                       .master_be_o      ( dm_master_be      ),
                       .master_gnt_i     ( '0                ),
                       .master_r_valid_i ( '0                ),
                       .master_r_rdata_i ( '0                ),
                       .dmi_rst_ni       ( reset_n           ),
                       .dmi_req_valid_i  ( dmi_req_valid   ),
                       .dmi_req_ready_o  ( dmi_req_ready   ),
                       .dmi_req_i        ( dmi_req_data    ),
                       .dmi_resp_valid_o ( dmi_resp_valid  ),
                       .dmi_resp_ready_i ( dmi_resp_ready  ),
                       .dmi_resp_o       ( dmi_resp_data   )
                       );

`define rv_echo(READY_OUT, VALID_IN, DATA_IN, READY_IN, VALID_OUT, DATA_OUT) \
  always_ff @(posedge clk) begin \
    if (!reset_n) begin \
      READY_OUT <= 0; \
      VALID_OUT <= 0; \
      DATA_OUT <= '0; \
    end \
    else begin \
      READY_OUT <= 1; \
      VALID_OUT <= 1; \
      if(VALID_IN) begin \
        READY_OUT <= 1; \
        DATA_OUT <= DATA_IN; \
      end \
      if(READY_IN) begin \
        VALID_OUT <= 1; \
      end \
    end \
  end

// `rv_echo(dmi_req_ready, dmi_req_valid, dmi_req_data, dmi_resp_ready, dmi_resp_valid, dmi_resp_data)

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
    send_data({ESC});
    send_data({CMD_READ,ADDR_IDCODE});

   send_data({ESC});
   send_data({CMD_WRITE,ADDR_DMI});
   send_data(8'b00000110);
   send_data(8'b00000000);
   send_data(8'b00000000);
   send_data(8'b00000000);
   send_data(8'b01000000);
   send_data(8'b11111100);

   send_data({ESC});
   send_data({CMD_WRITE,ADDR_DMI});
   send_data(8'b00000101);
   send_data(8'b00000000);
   send_data(8'b00000000);
   send_data(8'b00000000);
   send_data(8'b01000000);
   send_data(8'b11111100);

    send_data({ESC});
    send_data({CMD_READ,ADDR_DMI});

    for(int i = 0; i< 180; i++) begin
      @(posedge clk);
    end
    send_data({ESC});
    send_data({CMD_READ,ADDR_DTMCS});


   //  send_data({ESC});
   //  for(int i = 0; i< 10; i++) begin
   //    @(posedge clk);
   //  end
   //  send_data({CMD_READ,ADDR_DMI});
   //  @(posedge clk);



  endtask // test_read

  initial begin
    #80
      test_read();
    $display("All tests done.");

    $dumpfile("TB_UART_TAP_ASYNC_DUMP.vcd");
    $dumpvars;
  end


endmodule // TB_UART_DTM_ASYNC
