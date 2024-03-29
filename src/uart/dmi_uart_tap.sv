//                              -*- Mode: Verilog -*-
// Filename        : dmi_uart_tap_asynch.sv
// Description     : UART Test-Access-Point
// Author          : Stephan Proß
// Created On      : Fri Sep 09 16:44:56 2022
// Last Modified By: Stephan Proß
// Last Modified On: Tue Jan 10 16:44:56 2023
// Update Count    : 0
// Status          : Unknown, Use with caution!

import uart_pkg::*;


module DMI_UART_TAP #(
    parameter integer unsigned WIDTH = get_write_length(ADDR_DMI)
) (
    input  logic       CLK_I,
    input  logic       RST_NI,
    // UART-Interface connections
    output logic       READ_O,
    input  logic [7:0] DATA_REC_I,
    input  logic       RX_EMPTY_I,
    input  logic       CMD_REC_I,

    input  logic       TX_READY_I,
    output logic       WRITE_O,
    output logic [7:0] DATA_SEND_O,
    output logic       SEND_COMMAND_O,
    output logic [7:0] COMMAND_O,
    //DM Reset signals
    output logic       DMI_HARD_RESET_O,
    input  logic [1:0] DMI_ERROR_I,

    // Interconnect signals
    output logic [IRLENGTH-1:0] WRITE_ADDRESS_O,
    output logic [   WIDTH-1:0] WRITE_DATA_O,
    output logic                WRITE_VALID_O,
    input  logic                WRITE_READY_I,


    output logic [IRLENGTH-1:0] READ_ADDRESS_O,
    input  logic [   WIDTH-1:0] READ_DATA_I,
    input  logic                READ_VALID_I,
    output logic                READ_READY_O,
    input  logic [IRLENGTH-1:0] VALID_ADDRESS_I

);



  //-----------------------------------------------------------------------
  // ---- Command Decoder ----
  //-----------------------------------------------------------------------
  // Signals for easier address and command access.
  logic                 busy_decoding;

  logic [CMDLENGTH-1:0] write_command;
  logic [ IRLENGTH-1:0] write_address;
  logic                 receive_enable;

  logic                 rx_read;
  assign READ_O = rx_read;

  logic [CMDLENGTH-1:0] read_command;
  logic [ IRLENGTH-1:0] read_address;

  // Decoder to Read-Arbiter ready-valid
  logic                 read_arbiter_ready;
  logic                 read_arbiter_valid;

  // Decoder to Write-Arbiter ready-valid
  logic                 write_arbiter_ready;
  logic                 write_arbiter_valid;

  // Read when rx is not empty under the condition that either a deserialization
  // is running or, rx is a command and decoder is ready to decode.
  assign rx_read = !RX_EMPTY_I && ((!busy_decoding && CMD_REC_I) || receive_enable);

  COMMAND_DECODER command_decoder_i (
      // Outputs
      .BUSY_O               (busy_decoding),
      .WRITE_COMMAND_O      (write_command),
      .WRITE_ADDRESS_O      (write_address),
      .READ_COMMAND_O       (read_command),
      .READ_ADDRESS_O       (read_address),
      .READ_ARBITER_VALID_O (read_arbiter_valid),
      .WRITE_ARBITER_VALID_O(write_arbiter_valid),
      // Inputs
      .CLK_I                (CLK_I),
      .RST_NI               (RST_NI),
      .READ_I               (rx_read),
      .CMD_REC_I            (CMD_REC_I),
      .DATA_REC_I           (DATA_REC_I),
      .READ_ARBITER_READY_I (read_arbiter_ready),
      .WRITE_ARBITER_READY_I(write_arbiter_ready)
  );


  //-----------------------------------------------------------------------
  // ---- Deserialization process. -----
  //-----------------------------------------------------------------------


  localparam integer unsigned MAX_BYTES = (WIDTH + 7) / 8;
  localparam integer unsigned MAX_BITS = MAX_BYTES * 8;

  // Ingoing signals
  logic                        deser_reset;
  bit   [$clog2(MAX_BITS)-1:0] deser_length;

  // Outgoing signals
  logic                        deser_busy;
  logic                        deser_run;
  logic                        deser_done;
  assign WRITE_VALID_O = deser_done;
  logic [MAX_BITS-1:0] deser_data_out;



  RX_DESERIALIZER #(
      .MAX_BITS(MAX_BITS)
  ) rx_deser_i (
      // Outputs
      .BUSY_O     (deser_busy),
      .DONE_O     (deser_done),
      .DATA_O     (deser_data_out),
      // Inputs
      .CLK_I      (CLK_I),
      .RST_I      (!RST_NI || deser_reset),
      .LENGTH_I   (deser_length),
      .DATA_BYTE_I(DATA_REC_I),
      .RUN_I      (deser_run)
  );


  //-----------------------------------------------------------------------
  // ---- Write Arbiter Process. -----
  //-----------------------------------------------------------------------
  // Process controlling progress of deserialzier, data exchange with
  // write interconnect. Is able to hold reading of rx while data is
  // transmitted over write interconnect.
  logic [CMDLENGTH-1:0] current_write_command;
  logic [ IRLENGTH-1:0] current_write_address;
  logic [ MAX_BITS-1:0] write_data;
  assign WRITE_DATA_O = write_data[WIDTH-1:0];

  assign WRITE_ADDRESS_O = current_write_address;

  always_ff @(posedge CLK_I) begin : WRITE_ARBITER
    if (!RST_NI) begin

      write_arbiter_ready <= 0;
      current_write_command <= CMD_NOP;
      current_write_address <= '0;
      write_data <= '0;

      deser_reset <= 1;
      deser_run <= 0;
      deser_length <= get_write_length(ADDR_IDCODE);

      receive_enable <= 0;
    end else begin
      write_arbiter_ready <= 0;
      deser_reset <= 1;
      deser_run <= 0;
      receive_enable <= 0;

      if (write_arbiter_valid) begin
        // New write command has been received or address changed.
        // Cancel current deserialization progress. Update
        // deserialization length.
        deser_reset <= 1;
        write_arbiter_ready <= 1;
        write_data <= '0;
        current_write_command <= write_command;
        current_write_address <= write_address;
        deser_length <= get_write_length(write_address);
      end else begin

        if (current_write_command == CMD_RESET) begin
          deser_reset <= 1;
          current_write_command <= CMD_NOP;
          write_data <= '0;

        end else if (current_write_command == CMD_WRITE) begin
          // When writing, progress deserializer for each
          // received byte which is not a command.
          deser_reset <= 0;
          receive_enable <= !deser_done;
          deser_run <= !RX_EMPTY_I && !CMD_REC_I;
          // When done, transmit data over write interconnect
          // to target.
          if (deser_done) begin
            write_data <= deser_data_out;
            if (WRITE_READY_I) begin
              deser_reset <= 1;
            end
          end
        end  // if (current_write_command == CMD_WRITE)
      end  // else: !if(write_arbiter_valid)
    end  // else: !if(!RST_NI)
  end  // block: WRITE_ARBITER

  //---------------------------------------------------------------------
  // ---- Serializer Process. -----
  //---------------------------------------------------------------------
  // Ingoing signals
  bit   [$clog2(MAX_BITS)-1:0] ser_length;
  logic                        ser_reset;

  // Outgoing signals
  logic                        ser_busy;
  logic                        ser_run;
  logic                        ser_done;
  logic [                 7:0] ser_byte_out;
  assign DATA_SEND_O = ser_byte_out;


  TX_SERIALIZER #(
      .MAX_BITS(MAX_BITS)
  ) tx_ser_i (
      // Outputs
      .BUSY_O     (ser_busy),
      .DONE_O     (ser_done),
      .DATA_BYTE_O(ser_byte_out),
      .WRITE_O    (WRITE_O),
      // Inputs
      .CLK_I      (CLK_I),
      .RST_I      (!RST_NI || ser_reset),
      .RUN_I      (ser_run),
      .DATA_I     ({'0, READ_DATA_I}),
      .LENGTH_I   (ser_length),
      .READY_I    (TX_READY_I)
  );


  //-----------------------------------------------------------------------
  // ---- Read-Arbiter Process. -----
  //-----------------------------------------------------------------------
  // Process controlling reading of addressed registers and the related
  // serialization process. Is also capable of notifying the Host of
  // changes in the read address or newly available data to read.

  logic [IRLENGTH-1:0] current_read_address;
  assign READ_ADDRESS_O = current_read_address;

  logic [CMDLENGTH-1:0] current_read_command;

  logic                 send_command;
  assign SEND_COMMAND_O = send_command;


  always_ff @(posedge CLK_I) begin : READ_ARBITER
    if (!RST_NI) begin

      read_arbiter_ready <= 0;
      current_read_address <= ADDR_IDCODE;
      current_read_command <= CMD_NOP;

      COMMAND_O <= '0;
      send_command <= 0;

      ser_run <= 0;
      ser_reset <= 1;
      READ_READY_O <= 0;
    end else begin
      COMMAND_O <= '0;
      send_command <= 0;
      read_arbiter_ready <= 0;
      ser_run <= 0;
      ser_reset <= 0;
      READ_READY_O <= 0;

      // Address and command changes are only permitted outside of a running transaction.
      if (!ser_busy) begin
        // However, command and address changes by the arbiter are of higher priority.
        if (read_arbiter_valid) begin
          read_arbiter_ready <= 1;
          // Notify TAP if read address has changed.
          // Sending the command results in TX being busy.
          COMMAND_O <= {3'b000, read_address};
          send_command <= 1;

          current_read_address <= read_address;
          current_read_command <= read_command;
          ser_length <= get_read_length(read_address);
        end
      end

      if (current_read_command == CMD_RESET) begin
        ser_reset <= 1;
        current_read_command <= CMD_NOP;
      end else if (current_read_command == CMD_READ) begin
        // Read command will trigger read of address
        // exactly once.
        if (!ser_done) begin

          READ_READY_O <= !ser_busy;
          ser_run <= READ_VALID_I;
        end else begin
          ser_reset <= 1;
          current_read_command <= CMD_NOP;
        end
      end else if (current_read_command == CMD_CONT_READ) begin
        // Same as CMD_READ, but will not change command
        // to CMD_NOP after one read.
        if (!ser_done) begin
          READ_READY_O <= !ser_busy;
          ser_run <= READ_VALID_I;
        end else begin
          ser_reset <= 1;
        end
      end else begin
        // Without any transaction of higher priority, act on valids on interconnect.
        if (VALID_ADDRESS_I != ADDR_NOP) begin
          if (VALID_ADDRESS_I != current_read_address) begin
            // Update local address and serializer length,
            current_read_address <= VALID_ADDRESS_I;
            ser_length <= get_read_length(VALID_ADDRESS_I);
            // Notify TAP of changed read address.
            COMMAND_O <= {3'b000, VALID_ADDRESS_I};
            send_command <= 1;
          end else begin
            if (!ser_done) begin
              READ_READY_O <= !ser_busy;
              ser_run <= 1;
            end else begin
              ser_reset <= 1;
            end
          end
        end

      end
    end  // else: !if(!RST_NI)
  end  // block: READ_ARBITER



endmodule : DMI_UART_TAP
// Local Variables:
// verilog-library-flags:("-f ../../include.vc")
// End:
