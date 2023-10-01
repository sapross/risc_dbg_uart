//                              -*- Mode: Verilog -*-
// Filename        : UART_DTM_TOP.sv
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
module UART_DTM_TOP (  /*AUTOARG*/
    // Outputs
    debug_tx,
    led0,
    // Inputs
    clk_i,
    rst_i,
    debug_rx
);

  localparam integer CLK_RATE = 50 * 10 ** 6;
  localparam integer BAUD_RATE = 3 * 10 ** 6;

  input logic clk_i;
  input logic rst_i;

  input logic debug_rx;
  output logic debug_tx;

  output logic led0;

  logic sys_clk;
  assign led0 = !rst_i;

  clk_wiz_0 i_clk_wiz_0 (
      // Clock out ports
      .clk_out1(clk),
      // Status and control signals
      .reset(0),
      .locked(),
      // Clock in ports
      .clk_in1(clk_i)
  );


  logic clk;
  logic reset_n;
  assign reset_n = !rst_i;


  logic rx0, rx1;
  assign rx0 = debug_rx;
  logic tx0, tx1;
  assign debug_tx = tx0;

  logic        sw_channel;
  logic        dmi_req_ready;
  logic        dmi_req_valid;
  logic [40:0] dmi_req_data;
  logic        dmi_resp_ready;
  logic        dmi_resp_valid;
  logic [33:0] dmi_resp_data;

  logic        status_valid;
  logic [ 7:0] status;
  logic        control_ready;
  logic        stb_data_valid;
  logic [31:0] stb_data;
  logic        stb_data_ready;


  DTM_UART #(
      .ESC(ESC),
      .CLK_RATE(CLK_RATE),
      .BAUD_RATE(BAUD_RATE),
      .STB_CONTROL_WIDTH(8),
      .STB_STATUS_WIDTH(8),
      .STB_DATA_WIDTH(32)
  ) DUT (
      .CLK_I           (clk),
      .RST_NI          (reset_n),
      .RX0_I           (rx0),
      .RX1_O           (rx1),
      .TX0_O           (tx0),
      .TX1_I           (tx1),
      .DMI_REQ_READY_I (dmi_req_ready),
      .DMI_REQ_VALID_O (dmi_req_valid),
      .DMI_REQ_O       (dmi_req_data),
      .DMI_RESP_READY_O(dmi_resp_ready),
      .DMI_RESP_VALID_I(dmi_resp_valid),
      .DMI_RESP_I      (dmi_resp_data),

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

  logic            dm_slave_req;
  logic            dm_slave_we;
  logic [  64-1:0] dm_slave_addr;
  logic [64/8-1:0] dm_slave_be;
  logic [  64-1:0] dm_slave_wdata;
  logic [  64-1:0] dm_slave_rdata;

  logic            dm_master_req;
  logic [  64-1:0] dm_master_add;
  logic            dm_master_we;
  logic [  64-1:0] dm_master_wdata;
  logic [64/8-1:0] dm_master_be;
  logic            dm_master_gnt;
  logic            dm_master_r_valid;
  logic [  64-1:0] dm_master_r_rdata;
  logic            ndmreset;
  logic            dmactive;
  logic            debug_req_irq;

  localparam dm::hartinfo_t DebugHartInfo = '{
      zero1: '0,
      nscratch: 2,  // Debug module needs at least two scratch regs
      zero0: '0,
      dataaccess: 1'b1,  // data registers are memory mapped in the debugger
      datasize: dm::DataCount,
      dataaddr: dm::DataAddr
  };
  dm_top #(
      .NrHarts        (1),
      .BusWidth       (64),
      .SelectableHarts(1'b1)
  ) i_dm_top (
      .clk_i           (clk),
      .rst_ni          (reset_n),          // PoR
      .testmode_i      (1'b0),
      .ndmreset_o      (ndmreset),
      .dmactive_o      (dmactive),         // active debug session
      .debug_req_o     (debug_req_irq),
      .unavailable_i   ('0),
      .hartinfo_i      ({DebugHartInfo}),
      .slave_req_i     ('0),
      .slave_we_i      ('0),
      .slave_addr_i    ('0),
      .slave_be_i      ('0),
      .slave_wdata_i   ('0),
      .slave_rdata_o   (dm_slave_rdata),
      .master_req_o    (dm_master_req),
      .master_add_o    (dm_master_add),
      .master_we_o     (dm_master_we),
      .master_wdata_o  (dm_master_wdata),
      .master_be_o     (dm_master_be),
      .master_gnt_i    ('0),
      .master_r_valid_i('0),
      .master_r_rdata_i('0),
      .dmi_rst_ni      (reset_n),
      .dmi_req_valid_i (dmi_req_valid),
      .dmi_req_ready_o (dmi_req_ready),
      .dmi_req_i       (dmi_req_data),
      .dmi_resp_valid_o(dmi_resp_valid),
      .dmi_resp_ready_i(dmi_resp_ready),
      .dmi_resp_o      (dmi_resp_data)
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

  //`rv_echo(dmi_resp_ready, dmi_resp_valid, dmi_req_data, dmi_resp_ready, dmi_resp_valid,
  //         dmi_resp_data)

endmodule  // UART_DTM_TOP
