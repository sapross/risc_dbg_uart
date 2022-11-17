//                              -*- Mode: SystemVerilog -*-
// Filename        : de-serializer.sv
// Description     : Bytewise De-Serializer component performing both tasks simultaneously.
// Author          : Stephan Proß
// Created On      : Thu Nov 17 16:16:24 2022
// Last Modified By: Stephan Proß
// Last Modified On: Thu Nov 17 16:16:24 2022
// Update Count    : 0
// Status          : Unknown, Use with caution!
module DE_SERIALIZER #(
                       parameter integer MAX_BYTES = 1
                       )
(
 input logic                    CLK_I,
 input logic                    RST_NI,
 input logic [7:0]              NUM_BITS_I,
 input logic [7:0]              BYTE_I,
 input logic [8*MAX_BYTES-1:0]  REG_I,
 output logic [7:0]             BYTE_O,
 output logic [8*MAX_BYTES-1:0] REG_O,
 input logic                    RUN_I,
 output logic                   VALID_O,
 output logic                   DONE_O
 ) ;

  bit [$clog2(MAX_BYTES)-1:0]    byte_count;

  // Counter process. If if the number of bytes serialized is lower than the number
  // of bits, increase the count each cycle if counter is signaled to run.
  // Otherwise, if the count of bytes exceeds the number of serialized bits, set
  // done to high and wait until run is set to low to reset the counter.
  always_ff @(posedge CLK_I) begin : BYTE_COUNTER
    if(!RST_NI) begin
      byte_count <= 0;
      REG_O <= '0;
      BYTE_O = '0;
      VALID_O <= 0;
    end
    else begin
      if ( RUN_I ) begin
        // Have we de-/serialized the number bits given by NUM_BITS_I?
        if ( 8*byte_count < NUM_BITS_I ) begin
          byte_count <= byte_count + 1;

          BYTE_O = REG_I[8*(byte_count+1)-1 -: 8];
          REG_O[8*(byte_count+1)-1 -: 8] <= BYTE_I;

          VALID_O <= 1;
        end
        else begin
          VALID_O <= 0;
        end
      end
    end // else: !if(!RST_NI)
  end // block: BYTE_COUNTER


  always_comb begin : DONE
    if (!RST_NI) begin
      DONE_O = 0;
    end
    else begin
      if ( 8*byte_count < NUM_BITS_I ) begin
        DONE_O = 0;
      end
      else begin
        DONE_O = 1;
      end
    end // else: !if(!RST_NI)
  end // block: SERIALIZE

endmodule // DE_SERIALIZER
