-------------------------------------------------------------------------------
-- Title      : De-Serializer
-- Project    :
-------------------------------------------------------------------------------
-- File       : de-serializer.vhd
-- Author     : Stephan Proß  <s.pross@stud.uni-heidelberg.de>
-- Company    :
-- Created    : 2022-09-22
-- Last update: 2022-09-26
-- Platform   :
-- Standard   : VHDL'93/02
-------------------------------------------------------------------------------
-- Description: For a given register-size, performs byte-wise serialization and
-- deserialization.
-------------------------------------------------------------------------------
-- Copyright (c) 2022
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author  Description
-- 2022-09-22  1.0      spross  Created
-------------------------------------------------------------------------------

library IEEE;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.math_real.all;

entity DE_SERIALIZER is
  generic (
    MAX_BYTES : integer -- Number of bytes required for the largest register.
  );
  port (
    CLK      : in    std_logic;
    RST      : in    std_logic;
    NUM_BITS : unsigned(7 downto 0);  -- Number of bits of the target register.
    D_I      : in    std_logic_vector(7 downto 0);
    REG_I    : in    std_logic_vector(8 * MAX_BYTES - 1 downto 0);
    D_O      : out   std_logic_vector(7 downto 0);
    REG_O    : out   std_logic_vector(8 * MAX_BYTES - 1 downto 0);
    RUN_I    : in    std_logic;
    DONE_O   : out   std_logic
  );
end entity DE_SERIALIZER;

architecture BEHAVIORAL of DE_SERIALIZER is

  signal byte_count : integer range 0 to MAX_BYTES;
  signal done       : std_logic;

begin  -- architecture BEHAVIORAL

  DONE_O <= done;

  -- Counter process. If if the number of bytes serialized is lower than the number
  -- of bits, increase the count each cycle if counter is signaled to run.
  -- Otherwise, if the count of bytes exceeds the number of serialized bits, set
  -- done to high and wait until run is set to low to reset the counter.
  COUNTER : process (CLK) is
  begin

    if rising_edge(CLK) then
      if (RST = '1') then
        byte_count <= 0;
        done  <= '0';
      else
        -- Are we done serializing?
        if (to_unsigned(8*byte_count,NUM_BITS'length) < NUM_BITS) then
          -- If not, set done to low ...
          done <= '0';
          -- and increment the counter if run is high.
          if ( RUN_I = '1' ) then
            byte_count <= byte_count + 1;
          end if;
        else
          -- If we are done serializing set done to high and wait until run is
          -- set to low as ack.
          if ( RUN_I = '1' ) then
            done <= '1';
          else
            byte_count <= 0;
            done <= '0';
          end if;
        end if;
      end if;
    end if;

  end process COUNTER;

  -- Serialize REG_I into D_O and deserialize D_I into REG_O.
  MAIN : process (CLK) is
  begin

    if rising_edge(CLK) then
      if (RST = '1') then
        D_O   <= (others => '0');
        REG_O <= (others => '0');
      else
        if (to_unsigned(8 * (byte_count), NUM_BITS'length) < NUM_BITS) then
          D_O                                                   <= REG_I(8 * (byte_count + 1) - 1 downto 8 * byte_count);
          REG_O(8 * (byte_count + 1) - 1 downto 8 * byte_count) <= D_I;
        end if;
      end if;
    end if;

  end process MAIN;

end architecture BEHAVIORAL;
