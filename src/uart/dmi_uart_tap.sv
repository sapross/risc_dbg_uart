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


module DMI_UART_TAP
  #(
    parameter integer unsigned WIDTH = get_write_length(ADDR_DMI)
    )
  (
   input logic                 CLK_I ,
   input logic                 RST_NI ,
   // UART-Interface connections
   output logic                READ_O,
   input logic [7:0]           DATA_REC_I,
   input logic                 RX_EMPTY_I,
   input logic                 CMD_REC_I,

   input logic                 TX_READY_I,
   output logic                WRITE_O,
   output logic [7:0]          DATA_SEND_O,
   output logic                SEND_COMMAND_O,
   output logic [7:0]          COMMAND_O,
   //DM Reset signals
   output logic                DMI_HARD_RESET_O,
   input logic [1:0]           DMI_ERROR_I,

   // Interconnect signals
   output logic [IRLENGTH-1:0] WRITE_ADDRESS_O,
   output logic [WIDTH-1:0]    WRITE_DATA_O,
   output logic                WRITE_VALID_O,
   input logic                 WRITE_READY_I,


   output logic [IRLENGTH-1:0] READ_ADDRESS_O,
   input logic [WIDTH-1:0]     READ_DATA_I,
   input logic                 READ_VALID_I,
   output logic                READ_READY_O,
   input logic [IRLENGTH-1:0]  VALID_ADDRESS_I

   );



  //-----------------------------------------------------------------------
  // ---- Command Decoder ----
  //-----------------------------------------------------------------------
  // Signals for easier address and command access.
  logic [IRLENGTH-1:0]                 address;
  logic [CMDLENGTH-1:0]                command;

  logic                                busy_decoding;

  logic [CMDLENGTH-1:0]                write_command;
  logic [IRLENGTH-1:0]                 write_address;
  logic                                write_wait;
  logic                                receive_enable;

  logic                                rx_read;

  assign READ_O = rx_read;

  logic [CMDLENGTH-1:0]                read_command;
  logic [IRLENGTH-1:0]                 read_address;

  logic                                deser_reset;
  logic                                deser_busy;



  logic                                read_arbiter_ready;
  logic                                read_arbiter_valid;

  logic                                write_arbiter_ready;
  logic                                write_arbiter_valid;

  // Read when rx is not empty under the condition that either a deserialization
  // is running or, rx is a command and decoder is ready to decode.
  assign rx_read = !RX_EMPTY_I && ((!busy_decoding && CMD_REC_I) || receive_enable);

  always_ff @(posedge CLK_I) begin : DECODER
    if(!RST_NI) begin
      busy_decoding <= 0;
      address <= '0;
      command  <= CMD_NOP;

      read_arbiter_valid <= 0;
      read_address <= '0;
      read_command <= CMD_NOP;

      write_arbiter_valid <= 0;
      write_address <= '0;
      write_command <= CMD_NOP;

    end
    else begin

      read_arbiter_valid <= 0;
      write_arbiter_valid <= 0;
      // Process read data and decode command & address.
      if (rx_read && CMD_REC_I) begin
        busy_decoding <= 1;
        address <= DATA_REC_I[IRLENGTH-1:0];
        command <= DATA_REC_I[7:IRLENGTH];
      end
      if (busy_decoding) begin
        case (command)
          // Reset is communicated with the Arbiters.
          CMD_RESET : begin
            write_arbiter_valid <= 1;
            write_command <= CMD_RESET;
            write_address <= ADDR_IDCODE;

            read_arbiter_valid <= 1;
            read_command <= CMD_RESET;
            read_address <= address;
            if (read_arbiter_ready && write_arbiter_ready) begin
              busy_decoding <= 0;
            end
          end

          // Read commands do not change write_command and progress.
          CMD_READ : begin
            read_arbiter_valid <= 1;
            read_command <= CMD_READ;
            read_address <= address;
            if (read_arbiter_ready) begin
              busy_decoding <= 0;
            end
          end
          CMD_CONT_READ : begin
            read_arbiter_valid <= 1;
            read_command <= CMD_CONT_READ;
            read_address <= address;
            if (read_arbiter_ready) begin
              busy_decoding <= 0;
            end
          end

          // Only CMD_WRITE changes write variables.
          CMD_WRITE : begin
            write_arbiter_valid <= 1;
            write_command <= CMD_WRITE;
            write_address <= address;
            if (write_arbiter_ready) begin
              busy_decoding <= 0;
            end
          end
          default : begin
            busy_decoding <= 0;
          end
        endcase // case ( command )
      end // if (rx_read && CMD_REC_I)
    end // else: !if(!RST_NI)
  end // block: CMD_DECODE

  //-----------------------------------------------------------------------
  // ---- Deserialization process. -----
  //-----------------------------------------------------------------------
  localparam integer unsigned MAX_BYTES = (WIDTH + 7) / 8;
  localparam integer unsigned MAX_BITS = MAX_BYTES * 8;
  // Ingoing signals
  bit [$clog2(MAX_BITS)-1:0]  deser_length;
  logic [7:0]                 deser_byte_in;
  assign deser_byte_in = DATA_REC_I;

  // Outgoing signals
  bit [$clog2(MAX_BITS)-1:0]  deser_count;
  logic                       deser_run;
  logic                       deser_done;
  assign WRITE_VALID_O = deser_done;

  logic [MAX_BITS-1:0]        deser_reg;
  assign WRITE_DATA_O = deser_reg;

  always_ff @(posedge CLK_I) begin : DE_SERIALIZE
    if(!RST_NI || deser_reset) begin
      deser_count <= 0;
      deser_done <= 0;
      deser_busy <= 0;
      deser_reg <= '0;
    end
    else begin
      if (deser_count < deser_length) begin
        deser_done <= 0;
          if (deser_run) begin
            deser_busy <= 1;
            deser_reg[deser_count +: 8] <= deser_byte_in;
            deser_count <= deser_count + 8;
          end
      end
      else if (deser_busy) begin
        deser_done <= 1;
      end
    end
  end

  //-----------------------------------------------------------------------
  // ---- Write Arbiter Process. -----
  //-----------------------------------------------------------------------
  // Process controlling progress of deserialzier, data exchange with
  // write interconnect. Is able to hold reading of rx while data is
  // transmitted over write interconnect.
  logic [CMDLENGTH-1:0] current_write_command;
  logic [IRLENGTH-1:0]  current_write_address;
  assign WRITE_ADDRESS_O = current_write_address;

  always_ff @(posedge CLK_I) begin : WRITE_ARBITER
    if(!RST_NI) begin

      write_arbiter_ready <= 0;
      current_write_command <= CMD_NOP;
      current_write_address <= '0;

      deser_reset <= 0;
      deser_run <= 0;
      deser_length <= get_write_length(ADDR_IDCODE);

      receive_enable <= 0;
      write_wait <= 0;
    end
    else begin
      write_arbiter_ready <= 0;
      deser_reset <= 0;
      deser_run <= 0;
      receive_enable <= 0;
      write_wait <= 0;

      if (write_arbiter_valid) begin
        // New write command has been received or address changed.
        // Cancel current deserialization progress. Update
        // deserialization length.
        deser_reset <= 1;
        write_arbiter_ready <= 1;
        current_write_command <= write_command;
        current_write_address <= write_address;
        deser_length <= get_write_length(write_address);
      end
      else begin

        if (current_write_command == CMD_RESET) begin
          deser_reset <= 1;
          current_write_command <= CMD_NOP;
        end
        else if (current_write_command == CMD_WRITE) begin
          // When writing, progress deserializer for each
          // received byte which is not a command.
          receive_enable <= !deser_done && !deser_reset;
          deser_run <= !RX_EMPTY_I && !CMD_REC_I;
          // When done, transmit data over write interconnect
          // to target.
          if (deser_done) begin
            if (WRITE_READY_I) begin
              deser_reset <= 1;
            end
            else begin
              write_wait <= 1;
            end
          end
        end

      end
    end
  end // block: WRITE_ARBITER

  //---------------------------------------------------------------------
  // ---- Serializer Process. -----
  //---------------------------------------------------------------------
  // Ingoing signals
  bit [$clog2(MAX_BITS)-1:0]  ser_length;
  logic                       ser_reset;

  // Outgoing signals
  bit [$clog2(MAX_BITS)-1:0]  ser_count;
  logic                       ser_busy;
  logic                       ser_run;
  logic                       ser_done;
  logic [7:0]                 ser_byte_out;
  assign DATA_SEND_O = ser_byte_out;



  always_ff @(posedge CLK_I) begin : SERIALIZE
    if(!RST_NI || ser_reset) begin
      ser_count <= 0;
      ser_busy <= 0;
      ser_done <= 0;
      ser_byte_out <= '0;
    end
    else begin
      ser_done <= 0;
      if (ser_count < ser_length) begin
          if (ser_run) begin
            ser_busy <= 1;
            ser_byte_out <= READ_DATA_I[ser_count +: 8];
            ser_count <= ser_count + 8;
          end
      end
      else if (ser_busy) begin
        ser_done <= 1;
      end
    end
  end

  logic [IRLENGTH-1:0] current_read_address;
  assign READ_ADDRESS_O = current_read_address;

  logic [CMDLENGTH-1:0] current_read_command;

  logic                send_command;
  assign SEND_COMMAND_O = send_command;

  logic                tx_write;
  assign tx_write = TX_READY_I && ser_run && !send_command;
  assign WRITE_O = tx_write;

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
    end
    else begin
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
      end
      else  if (current_read_command == CMD_READ) begin
        // Read command will trigger read of address
        // exactly once.
        if (!ser_done) begin
          READ_READY_O <= !ser_busy;
          ser_run <= (TX_READY_I && !tx_write) && (READ_VALID_I || ser_busy);
        end
        else begin
          ser_reset <= 1;
          current_read_command <= CMD_NOP;
        end
      end else if( current_read_command == CMD_CONT_READ ) begin
        // Same as CMD_READ, but will not change command
        // to CMD_NOP after one read.
        if (!ser_done) begin
          READ_READY_O <= !ser_busy;
          ser_run <= (TX_READY_I && !tx_write) && (READ_VALID_I || ser_busy);
        end
        else begin
          ser_reset <= 1;
        end
      end
      else begin
        // Without any transaction of higher priority, act on valids on interconnect.
        if(VALID_ADDRESS_I != ADDR_NOP) begin
          if (VALID_ADDRESS_I != current_read_address) begin
            // Update local address and serializer length,
            current_read_address <= VALID_ADDRESS_I;
            ser_length <= get_read_length(VALID_ADDRESS_I);
            // Notify TAP of changed read address.
            COMMAND_O <= {3'b000, VALID_ADDRESS_I};
            send_command <= 1;
          end
          else begin
            if (!ser_done) begin
              READ_READY_O <= !ser_busy;
              ser_run <= (TX_READY_I && !tx_write) && (READ_VALID_I || ser_busy);
            end
            else begin
              ser_reset <= 1;
            end
          end
        end

        end
    end // else: !if(!RST_NI)
  end // block: READ_ARBITER



endmodule : DMI_UART_TAP
