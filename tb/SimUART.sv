// See LICENSE.SiFive for license details.
//VCS coverage exclude_file
import "DPI-C" function void uart_tick
(
 output bit uart_rx,
 input bit  uart_tx
);

module SimUART #(
                 parameter TICK_DELAY = 50
                 )(
                   input         clock,
                   input         reset,

                   input         enable,
                   input         init_done,

                   output        uart_tx,
                   input         uart_rx,

                   input         uart_rx_driven,

                   output [31:0] exit
                   );

   reg [31:0]                    tickCounterReg;
   wire [31:0]                   tickCounterNxt;

   assign tickCounterNxt = (tickCounterReg == 0) ? TICK_DELAY :  (tickCounterReg - 1);

   bit          r_reset;

   wire         #0.1 __uart_rx = uart_rx_driven ?
                uart_rx : 1;

   bit          __uart_tx;
   bit          __uart_rx;
   int          __exit;

   reg          init_done_sticky;

   assign #0.1 uart_tx = __uart_tx;

   assign #0.1 exit = __exit;

   always @(posedge clock) begin
      r_reset <= reset;
      if (reset || r_reset) begin
         __exit = 0;
         tickCounterReg <= TICK_DELAY;
         init_done_sticky <= 1'b0;
      end else begin
         init_done_sticky <= init_done | init_done_sticky;
         if (enable && init_done_sticky) begin
            tickCounterReg <= tickCounterNxt;
            if (tickCounterReg == 0) begin
               uart_tick(__uart_rx,
                         __uart_tx);
              __exit = 0;
            end
         end // if (enable && init_done_sticky)
      end // else: !if(reset || r_reset)
   end // always @ (posedge clock)

endmodule
