/* File:   dmi_uart_tap.sv
 * Author: Stephan Proß <s.pross@stud.uni-heidelberg.de>
 * Date:   07.09.2022
 *
 * Description: UART TAP for DMI (according to debug spec 0.13)
 */
import uart_pkg::*;

module DMI_UART_TAP #(
                      parameter int CLK_RATE = 100000000,
                      parameter int BAUD_RATE = 3*10**6
                      )(
                        input logic                         CLK_I ,
                        input logic                         RST_NI ,
                        // UART-Interface connections
                        output logic                        RE_O,
                        output logic                        WE_O,
                        input logic                         TX_READY_I,
                        input logic                         RX_EMPTY_I,
                        output logic [7:0]                  DSEND_O,
                        input logic [7:0]                   DREC_I,

                        //DM Reset signals
                        output logic                        DMI_HARD_RESET_O,
                        input logic [1:0]                   DMI_ERROR_I,

                        // DM-Interface connections
                        output logic                        DMI_READ_O,
                        output logic                        DMI_WRITE_O,
                        output logic [$bits(dmi_req_t)-1:0] DMI_O,
                        input logic [$bits(dmi_req_t)-1:0]  DMI_I,
                        input logic                         DMI_DONE_I
                        );

  typedef enum                                              {
                                                             st_idle,
                                                             st_cmdaddr,
                                                             st_header,
                                                             st_length,
                                                             st_read,
                                                             st_write,
                                                             st_reset
                                                             } state_t;

  typedef struct                                            packed {
    logic [$bits(dmi_req_t)-1:0]                              dmi;
    // FSM Signals
    state_t state;
    logic [IRLENGTH-1:0]                                    address;
    logic [CMDLENGTH-1:0]                                   cmd;
    bit [7:0]                                               data_length;
    // Signals triggering waiting for respective dmi operations.
    logic                                                   dmi_wait_read;
    logic                                                   dmi_wait_write;
  } fsm_t;

  // State machine and combinatorial next state.
  fsm_t fsm, fsm_next;
  // Debug Transport Module Control Register.
  dtmcs_t                          dtmcs, dtmcs_next;
  // UART-Interface Signals
  logic                                                     we;
  logic                                                     re;
  // DMI-Interface Signals
  // MAX_BYTES = ceil($bits(dmi_req_t)/8)
  localparam integer                                        MAX_BYTES = ($bits(dmi_req_t) + 7) / 8;
  logic                                                     dmi_read;
  logic                                                     dmi_write;

  // Serializer Signals
  logic                                                     ser_reset;
  logic                                                     ser_run;
  logic                                                     ser_valid;
  logic                                                     ser_done;
  bit [7:0]                                                 ser_num_bits;
  logic [7:0]                                               ser_data_in;
  logic [8*MAX_BYTES-1:0]                                   ser_reg_in;
  logic [8*MAX_BYTES-1:0]                                   ser_reg_out;

  // Time Out timer to catch unfished operations.
  // Each UART-Frame takes 10 baud periods (1 Start + 8 Data + 1 Stop)
  // Wait for the time of 5 UART-Frames.
  localparam integer                                        MSG_TIMEOUT  = 5 * (10 * CLK_RATE / BAUD_RATE);
  bit [$clog2(MSG_TIMEOUT)-1:0]                             msg_timer;
  logic                                                     timer_overflow;

  // Function containing condition to run the timer for timeout.
  function automatic logic run_timer( state_t s, logic rx_empty);
    if ( rx_empty == 1 && (
                           s == st_cmdaddr ||
                           s == st_length  ||
                           s == st_read    ||
                           s == st_write
                           ) ) begin
      return 1;
    end
    else begin
      return 0;
    end; // else: !if( rx_empty == 1 && (...
  endfunction // run_timer

  assign DMI_HARD_RESET_O = dtmcs.dmihardreset;
  assign DMI_READ_O = dmi_read;
  assign DMI_WRITE_O = dmi_write;
  assign DMI_O = fsm.dmi;
  assign WE_O = we;
  assign RE_O = re;

  DE_SERIALIZER #(
                  .MAX_BYTES( MAX_BYTES )
                  ) DE_SERIALIZER_I
    (
     .CLK_I      ( CLK_I        ),
     .RST_NI     ( ser_reset    ),
     .NUM_BITS_I ( ser_num_bits ),
     .BYTE_I     ( DREC_I       ),
     .REG_I      ( ser_reg_in   ),
     .BYTE_O     ( DSEND_O      ),
     .REG_O      ( ser_reg_out  ),
     .RUN_I      ( ser_run      ),
     .VALID_O    ( ser_valid    ),
     .DONE_O     ( ser_done     )
     ) ;


  always_ff @(posedge CLK_I) begin : TIMEOUT_COUNTER
    if ( !RST_NI || !run_timer(fsm.state, RX_EMPTY_I) ) begin
      msg_timer <= 0;
      timer_overflow <= 0;
    end
    else begin
      msg_timer <= msg_timer + 1;
      if(msg_timer == MSG_TIMEOUT) begin
        timer_overflow <= 1;
      end
    end
  end // block: TIMEOUT_COUNTER

  always_ff @(posedge CLK_I) begin : FSM_CORE
    if ( !RST_NI ) begin
      // DTMCS register control.
      dtmcs.zero1 = '0;
      dtmcs.dmihardreset = 0;
      dtmcs.dmireset = 0;
      dtmcs.zero0 = 0;
      dtmcs.idle = 3'b001;
      dtmcs.dmistat <= DMINoError;
      dtmcs.abits <= $unsigned(ABITS);
      dtmcs.version <= 4'h01;
      // FSM state transitions.
      fsm.dmi <= '0;
      fsm.state <= st_idle;
      fsm.address <= ADDR_IDCODE;
      fsm.cmd <= CMD_NOP;

    end // if ( !RST_NI )
    else begin
      fsm <= fsm_next;
      // DTMCS transistions. Not all bits are writeable.
      dtmcs.dmihardreset <= dtmcs_next.dmihardreset;
      dtmcs.dmireset <= dtmcs_next.dmireset;
      dtmcs.idle <= dtmcs_next.idle;
      if (fsm.address == ADDR_DMI && timer_overflow == 1) begin
        if ( fsm.dmi_wait_read == 1 || fsm.dmi_wait_write == 1 ) begin
          dtmcs.dmistat <= DMIBusy;
        end
      end
      else if (fsm.address == ADDR_DTMCS && fsm.state == st_write) begin
        dtmcs.dmistat <= DMINoError;
      end
    end // else: !if( !RST_NI )
  end // block: FSM_CORE

  always_comb begin : FSM
    fsm_next = fsm;
    dtmcs_next = dtmcs;
    // UART-Interface
    re = 0;
    we = 0;
    // DMI-Interface
    dmi_read = 0;
    dmi_write = 0;
    //Serializer
    ser_reset = 0;
    ser_run = 0;
    ser_data_in = '0;
    ser_reg_in = '0;
    ser_num_bits = 1;

    case (fsm.state)
      st_idle: begin
        // FSM state variables
        fsm_next.cmd = CMD_NOP;
        fsm_next.data_length = '0;

        fsm_next.dmi_wait_read = 1;
        fsm_next.dmi_wait_write = 1;

        // If dmihardreset or dmireset bits of dtmcs are high, trigger reset.
        if ( dtmcs.dmihardreset == 1 ) begin
          fsm_next.state = st_reset;
        end
        else begin
          fsm_next.state = st_header;
        end
      end // case: st_idle

      st_header: begin
        // If RX-Fifo is not empty, read and check received byte for HEADER.
        if (RX_EMPTY_I == 0) begin
          re = 1;
          // Is the byte from RX fifo equal to our header?
          if (DREC_I == HEADER) begin
            // If yes, proceed to CmdAddr.
            fsm_next.state = st_cmdaddr;
          end
        end
      end

      st_cmdaddr: begin
        // If RX-Fifo is not empty, read and apply received byte to cmd and
        // address.
        if (RX_EMPTY_I == 0) begin
          re = 1;
          // Decode into command and address.
          fsm_next.cmd = DREC_I[7:IRLENGTH];
          fsm_next.address = DREC_I[IRLENGTH-1:0];
          // Move to the next state
          fsm_next.state = st_length;
        end
        else if (timer_overflow == 1) begin
          fsm_next.state = st_idle;
        end
      end // case: st_cmdaddr

      st_length: begin
        // If RX-Fifo is not empty, read and apply received byte to
        // data_length.
        if ( RX_EMPTY_I == 0 ) begin
          re = 1;
          // Apply byte as unsigned integer to data_length.
          fsm_next.data_length  = DREC_I;
          // If address is to a dmi register, trigger waiting.
          if (fsm.address == ADDR_DMI) begin
            fsm_next.dmi_wait_read   = 1;
            fsm_next.dmi_wait_write  = 1;
          end;
          // Move on to the next state determined by command.
          case (fsm.cmd)
            CMD_READ : begin
              fsm_next.state  = st_read;
            end
            CMD_WRITE : begin
              fsm_next.state  = st_write;
            end
            CMD_RESET : begin
              fsm_next.state  = st_reset;
            end
            default : begin
              fsm_next.state  = st_idle;
            end
          endcase
        end // if ( RX_EMPTY_I == 0 )
        else begin
          // Have we hit the message timeout? If yes, back to idle.
          if (timer_overflow == 1) begin
            fsm_next.state  = st_idle;
          end
        end // else: !if( RX_EMPTY_I == 0 )
      end // case: st_length

      st_read: begin
        // Serialize addressed register into bytes and send over TX.
        // De-/Serializer is active during this state.
        ser_reset = 1;
        // If serialization is not done...
        // and we do not need to wait for dmi...
        if (fsm.dmi_wait_read == 1) begin
          // If we do have to wait for dmi...
          if (DMI_DONE_I == 0 && timer_overflow == 0) begin
            // ...tell dmi_handler to read...
            fsm_next.dmi_wait_read = 1;
            dmi_read               = 1;
          end
          else begin
            //- ...otherwise we're done.
            fsm_next.dmi_wait_read = 0;
            dmi_read               = 0;
            fsm_next.dmi           = DMI_I;
          end // else: !if(DMI_DONE_I == 0 && timer_overflow == 0)
        end // if (fsm.dmi_wait_read == 1)
        else begin
          // always write to TX if ready.
          we      = TX_READY_I & ser_valid;
          ser_run = TX_READY_I;
          if (ser_done == 1) begin
            // We are done sending if our serializer is done.
            fsm_next.state = st_idle;
          end
        end // else: !if(fsm.dmi_wait_read == 1)

        case (fsm.address)
          // Dependent on address, load up the serializers register input
          // with the appropriate data.
          ADDR_IDCODE : begin
            ser_reg_in[$size(ser_reg_in) - 1 : $size(IDCODEVALUE)] = '0;
            ser_reg_in[$size(IDCODEVALUE) - 1 : 0]            = IDCODEVALUE;
            // IDCODE Register has 32 bits.
            ser_num_bits = 32;
          end
          ADDR_DTMCS : begin
            ser_reg_in[$size(ser_reg_in) - 1 : $size(dtmcs)] = '0;
            ser_reg_in[$size(dtmcs) - 1 : 0]                 = dtmcs;

            ser_num_bits = $size(dtmcs);
          end
          ADDR_DMI : begin
            // Read to dmi returns less bits than required to write since
            // dmi_req) > dmi_resp)
            ser_reg_in[$size(ser_reg_in) - 1 : $bits(dmi_req_t)] = '0;
            ser_reg_in[$bits(dmi_req_t) - 1 : 0]                 = fsm.dmi[$bits(dmi_req_t) - 1:0];

            ser_num_bits = $size(fsm.dmi);
          end
          default : begin
            fsm_next.state = st_idle;
          end
        endcase
      end // case: st_read

      st_write: begin
        // Deserialze bytes received over RX into addressed register.
        // De-/Serializer is active during this state.
        ser_reset = 1;
        if (timer_overflow == 1) begin
          // Message timeout is reached.
          fsm_next.state = st_idle;
        end
        else begin
          // Deserialization done?
          if (ser_done == 0) begin
            // Always read when rx-fifo is not empty:
            if (RX_EMPTY_I == 0) begin
              re      = 1;
              ser_run = 1;
            end
            else begin
              re      = 0;
              ser_run = 0;
            end
          end // if (ser_done == 0)
          else begin
            // Deserializing is done.
            // Do we need to write to and wait for dmi?
            if (fsm.dmi_wait_write == 1) begin
              // Is the dmi_handler done?
              if (DMI_DONE_I == 0) begin
                fsm_next.dmi_wait_write = 1;
                dmi_write               = 1;
              end
              else begin
                fsm_next.dmi_wait_write = 0;
                dmi_write               = 0;
              end
            end // if (fsm.dmi_wait_write = 1)
            else begin
              // Either dmi write is done or we didn't need to wait for the
              // handler anyway.
              fsm_next.state = st_idle;
            end
          end // else: !if(ser_done == 1)
        end // if (timer_overflow == 1)

        case (fsm.address)
          // Address decides into which register DREC_I is serialized into.
          ADDR_DTMCS : begin
            ser_num_bits = $size(dtmcs);
            if (ser_done == 1) begin
              dtmcs_next = ser_reg_out[$size(dtmcs) - 1 : 0];
            end
          end

          ADDR_DMI : begin
            ser_num_bits = $size(fsm.dmi);
            if (ser_done == 1) begin
              fsm_next.dmi = ser_reg_out[$size(fsm.dmi) - 1 : 0];
            end
          end

          default : begin
            fsm_next.state = st_idle;
            ser_reset      = 0;
          end
        endcase // case (fsm.address)

      end
      st_reset: begin
        // Reset state as the result of a reset command from host system.
        fsm_next.state   = st_idle;
        fsm_next.address = ADDR_IDCODE;
        dtmcs_next       = '0;
        fsm_next.dmi     = '0;
        // Stop serialization.
        ser_reset = 0;
        ser_run   = 0;
      end
    endcase // case (fsm.state)
  end // block: FSM

endmodule : DMI_UART_TAP
