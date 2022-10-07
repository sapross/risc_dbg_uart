-------------------------------------------------------------------------------
-- Title      : De-Serializer
-- Project    :
-------------------------------------------------------------------------------
-- File       : de-serializer.vhd
-- Author     : Stephan Proß  <s.pross@stud.uni-heidelberg.de>
-- Company    :
-- Created    : 2022-09-22
-- Last update: 2022-10-06
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
    CLK        : in    std_logic;
    RST        : in    std_logic;
    NUM_BITS_I : in    unsigned(7 downto 0);  -- Number of bits of the target register.
    D_I        : in    std_logic_vector(7 downto 0);
    REG_I      : in    std_logic_vector(8 * MAX_BYTES - 1 downto 0);
    D_O        : out   std_logic_vector(7 downto 0);
    REG_O      : out   std_logic_vector(8 * MAX_BYTES - 1 downto 0);
    RUN_I      : in    std_logic;
    DONE_O     : out   std_logic
  );
end entity DE_SERIALIZER;

architecture BEHAVIORAL of DE_SERIALIZER is

  signal count, count_next : integer range 0 to MAX_BYTES;
  -- signal ser_in, ser_out : std_logic_vector(8*MAX_BYTES-1 downto 0);
begin  -- architecture BEHAVIORAL

  -- Counter process. If if the number of bytes serialized is lower than the number
  -- of bits, increase the count each cycle if counter is signaled to run.
  -- Otherwise, if the count of bytes exceeds the number of serialized bits, set
  -- done to high and wait until run is set to low to reset the counter.
  COUNTER : process (CLK) is
  begin

    if rising_edge(CLK) then
      if (RST = '1') then
        count <= 0;
      else
        count <= count_next;
        -- Are we done serializing?
      end if;
    end if;

  end process COUNTER;

  COUNT_COMB : process (count, NUM_BITS_I, RUN_I) is
  begin

    count_next <= count;

    if (to_unsigned(8 * (count + 1), NUM_BITS_I'length) < NUM_BITS_I) then
      -- If not, increment the counter if run is high.
      if (RUN_I = '1') then
        count_next <= count + 1;
      end if;
    end if;

  end process COUNT_COMB;

  DONE_PROC : process (RST, count, NUM_BITS_I) is
  begin

    if (to_unsigned(8 * (count + 1), NUM_BITS_I'length) < NUM_BITS_I or RST = '1') then
      DONE_O <= '0';
    else
      DONE_O <= '1';
    end if;

  end process DONE_PROC;

  -- SHIFT_IN : process (CLK) is
  -- begin
  --   if (RST = '1') then
  --     sr_in <= ( others => '0' );
  --   else
  --     if (to_unsigned(8 * count, NUM_BITS_I'length) < NUM_BITS_I) then
  --       sr_in <= sr_in(sr_in'length - 8 - 1 downto 0) & D_I;
  --     end if;
  --   end if;

  -- end process;
  -- REG_O <= sr_in;

  -- SHIFT_OUT : process (CLK) is
  -- begin
  --   if (RST = '1') then
  --     sr_out <= ( others => '0' );
  --   else
  --     if (count = 0) then
  --       sr_out <= "00000000" & REG_I(REG_I'length -1 downto 8);
  --       D_O <= REG_I(7 downto 0);
  --     else
  --       sr_out <= "00000000" & sr_out(sr_out'length - 1 downto 8) ;
  --       D_O <= sr_out(7 downto 0);
  --     end if;
  --   end if;

  -- end process;

  -- Serialize REG_I into D_O and deserialize D_I into REG_O.
  DESERIALIZE : process (CLK) is
  begin

    if rising_edge(CLK) then
      if (RST = '1') then
        REG_O <= (others => '0');
      else
        REG_O(8 * (count + 1) - 1 downto 8 * count) <= D_I;
      end if;
    end if;

  end process DESERIALIZE;

  SERIALIZE : process (CLK) is
  begin

    if rising_edge(CLK) then
      if (RST = '1') then
        D_O <= (others => '0');
      else
        D_O <= REG_I(8 * (count + 1) - 1 downto 8 * count);
      end if;
    end if;

  end process SERIALIZE;


end architecture BEHAVIORAL;
