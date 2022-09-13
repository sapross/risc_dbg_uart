/* File:   dmi_uart_tap.sv
 * Author: Stephan Proß <s.pross@stud.uni-heidelberg.de>
 * Date:   07.09.2022
 *
 * Description: UART TAP for DMI (according to debug spec 0.13)
 */


module dmi_uart_tap #(
                      parameter int unsigned CLK_RATE = 100000000,
                      parameter int unsigned BAUD_RATE = 3*10**6,
                      parameter int unsigned IrLength = 5,
                      parameter logic [31:0] IdcodeValue = 32'h00000001,
                      parameter logic        BYPASS = 0,
                      parameter logic [7:0]  HEADER = 8'h01
                      )(
                        input logic  clk_i ,
                        input logic  rst_ni ,
                        input logic  testmode_i,

                        output logic dmi_rst_no, // hard reset

                        output       dm::dmi_req_t dmi_req_o,
                        output logic dmi_req_valid_o,
                        input logic  dmi_req_ready_i,

                        input        dm::dmi_resp_t dmi_resp_i,
                        output logic dmi_resp_ready_o,
                        input logic  dmi_resp_valid_i
                        );


  // UART signals
  logic                              re,        re_next;
  logic                              we,        we_next;

  logic                              tx_ready;
  logic                              rx_empty,  rx_full;

  typedef enum                       logic [IrLength-1:0] {
                                                           BYPASS0   = 'h0,
                                                           IDCODE    = 'h1,
                                                           DTMCSR    = 'h10,
                                                           DMIACCESS = 'h11,
                                                           BYPASS1   = 'h1f
                                                           } ir_reg_e;
  typedef struct                     packed {
    logic [31:18]                    zero1;
    logic                            dmihardreset;
    logic                            dmireset;
    logic                            zero0;
    logic [14:12]                    idle;
    logic [11:10]                    dmistat;
    logic [9:4]                      abits;
    logic [3:0]                      version;
  } dtmcs_t;

  dtmcs_t   dtmcs;
  dtmcs_t dtmcs_next;


  typedef enum                       logic [2:0] {st_idle, st_header, st_cmdaddr, st_length, st_data} state_t;
  state_t state,     state_next;

  typedef struct                     packed {
    logic [7-IrLength:0]             cmd;
    logic [IrLength-1:0]             address;
  } cmdaddr_t;

  typedef enum                       logic [7-IrLength:0] {
                                                           CMD_READ   = 'h0,
                                                           CMD_WRITE    = 'h2,
                                                           CMD_RESET    = 'h4,
                                                           } cmd_e;
  cmdaddr_t cmdaddr, cmdaddr_next;
  logic [IrLength-1:0]               address,   address_next;
  logic [7-IrLength:0]               cmd, cmd_next;
  assign cmdaddr.cmd = cmd;
  assign cmdaddr.address = address;

  assign cmdaddr_next.cmd = cmd_next;
  assign cmdaddr_next.address = address;


  int unsigned                       data_length, data_length_next;

  // Counts the number of bytes received to that register:
  int unsigned                       data_count;
  int unsigned                       data_count_next;
  int unsigned                       num_bytes, num_bytes_next;


  task send_register (
                      // Register to send.
                      input logic [7:0]   value,
                      // Current number of send block.
                      input int unsigned  blkcount_reg,
                      // Next value for outgoing register.
                      output logic [7:0]  data_next,
                      // Next value for current send block.
                      output int unsigned blkcount_next_reg,
                      // Only relevant to decide if next state should be;
                      // st_idle, or, if read buffer is not empty, st_read.
                      input logic         rx_empty_reg,
                      output logic        re_next_reg,
                      output logic        state_next_reg

                      );
    begin

      if (blkcount < ($size(value) / 8)) begin
        data_next         <= value[8 * (blkcount_reg + 1) - 1 : 8 * blkcount_reg];
        blkcount_next_reg <= blkcount_reg + 1;
      end else begin
        if (blkcount === ($size(value) / 8) && $size(value) % 8 > 0) begin
          // Handle remainder:
          // Fill leading bits with zero.
          data_next[7 : $size(value) % 8] <= 0;
          // Put remainder of the register in the lower bits.
          data_next[($size(value) % 8) - 1 : 0] <= value[$size(value) - 1 : 8 * blkcount_reg];
          blkcount_next_reg                            <= blkcount_reg + 1;
        end else begin
          blkcount_next_reg <= 0;
          if (rx_empty_reg) begin
            state_next_reg <= st_idle;
          end else begin
            state_next_reg <= st_decode;
            re_next_reg    <= 1;
          end
        end // else: !if(blkcount === ($size(value) / 8) && $size(value) % 8 > 0)
      end // else: !if(blkcount < ($size(value) / 8))
    end
  endtask // send_register

  task read_register (
                      // Register to send.
                      input logic [7:0]   value,
                      // Current number of send block.
                      input int unsigned  blkcount_reg,
                      // Next value for outgoing register.
                      output logic [7:0]  data_next,
                      // Next value for current send block.
                      output int unsigned blkcount_next_reg,
                      // Only relevant to decide if next state should be;
                      // st_idle, or, if read buffer is not empty, st_read.
                      input logic         rx_empty_reg,
                      output logic        re_next_reg,
                      output logic        state_next_reg

                      );
    begin

      if (blkcount < ($size(value) / 8)) begin
        data_next         <= value[8 * (blkcount_reg + 1) - 1 : 8 * blkcount_reg];
        blkcount_next_reg <= blkcount_reg + 1;
      end else begin
        if (blkcount === ($size(value) / 8) && $size(value) % 8 > 0) begin
          // Handle remainder:
          // Fill leading bits with zero.
          data_next[7 : $size(value) % 8] <= 0;
          // Put remainder of the register in the lower bits.
          data_next[($size(value) % 8) - 1 : 0] <= value[$size(value) - 1 : 8 * blkcount_reg];
          blkcount_next_reg                            <= blkcount_reg + 1;
        end else begin
          blkcount_next_reg <= 0;
          if (rx_empty_reg) begin
            state_next_reg <= st_idle;
          end else begin
            state_next_reg <= st_decode;
            re_next_reg    <= 1;
          end
        end // else: !if(blkcount === ($size(value) / 8) && $size(value) % 8 > 0)
      end // else: !if(blkcount < ($size(value) / 8))
    end
  endtask // send_register
  uart #(
         .CLK_RATE(CLK_RATE),
         .BAUD_RATE(BAUD_RATE)
         ) i_uart(
                  .clk_i(clk_i),
                  .rst_ni(rst_ni),
                  .RX(RX),
                  .TX(TX),
                  .RE(re),
                  .WE(we),
                  .TX_READY(tx_ready),
                  .RX_EMPTY(rx_empty),
                  .RX_FULL(rx_full),
                  .DIN(data_send),
                  .DOUT(data_read)
                  );

  always_ff @(posedge clk_i or negedge rst_ni) begin : fsm_core
    if (!rst_ni) begin
      state     <= st_idle;
      blkcount  <= 0;
      re        <= 0;
      we        <= 0;
      data_send <= 0;
      address   <= 'h01;
      data_read <= 0;
      dtmcs     <= 0;
      dmi       <= 0;
    end else begin
      state     <= state_next;
      blkcount  <= blkcount_next;
      re        <= re_next;
      we        <= we_next;
      data_send <= data_send_next;
      address   <= address_next;
      data_read <= data_read_next;
      dtmcs     <= dtmcs_next;
      dmi       <= dmi_next;
    end
  end

  always_comb begin : fsm
    unique case (state)

      st_idle: begin
        state_next     <= st_idle;
        re_next        <= 0;
        address_next   <= address;
        cmd_next       <= cmd;
        dtmcs_next     <= dtmcs;
        dmi_next       <= dmi;

        if (rx_empty) begin
          re_next    <= 1;
          state_next <= st_header;
        end
      end // case: st_idle


      st_header: begin
        state_next <= st_header;
        if (!rx_empty) begin
          re_next <= 1;
        end else begin
          re_next <= 0;
        end
        if (re && data_read === HEADER) begin
          // data_read is valid and equals HEADER.
          state_next <= st_cmdaddr;
        end
      end // case: st_header

      st_cmdaddr: begin
        state_next <= st_cmdaddr;
        if (!rx_empty) begin
          re_next <= 1;
        end else begin
          re_next <= 0;
        end
        // Stay in st_cmdaddr until data_read is valid.
        if (re) begin
          cmd_next <= data_read[7:IrLength];
          address_next <= data_read[IrLength-1:0];
          state_next <= st_length;
        end

      end // case: st_cmdaddr

      st_length: begin
        state_next <= st_length;
        if (!rx_empty) begin
          re_next <= 1;
        end else begin
          re_next <= 0;
        end
        if ( re ) begin
          data_length_next <= data_read;
          data_count_next <= 0;
          state_next <= st_data;
        end
      end // case: st_length

      st_write: begin
        state_next <= st_write;
        if (!rx_empty) begin
          re_next <= 1;
        end else begin
          re_next <= 0;
        end
        if( re ) begin

          if( data_count === data_length -1 ) begin
            data_count_next <= 0;
            state_next <= st_header;
          end else begin
            data_count_next <= data_count + 1;
          end

        end

      end


      st_data: begin
        state_next <= st_data;
        if (!rx_empty) begin
          re_next <= 1;
        end else begin
          re_next <= 0;
        end
        if ( re ) begin
          if( data_count === data_length -1 ) begin
            data_count_next <= 0;
            state_next <= st_header;
          end else begin
            data_count_next <= data_count + 1;
          end
        end // if ( re )
      end // case: st_data




    endcase // unique case (state)
  end // block: fsm

endmodule : dmi_uart_tap
