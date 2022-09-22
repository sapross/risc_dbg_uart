-------------------------------------------------------------------------------
-- Title      : De-Serializer
-- Project    :
-------------------------------------------------------------------------------
-- File       : de-serializer.vhd
-- Author     : Stephan Proß  <s.pross@stud.uni-heidelberg.de>
-- Company    :
-- Created    : 2022-09-22
-- Last update: 2022-09-22
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
  use IEEE.STD_LOGIC_1164.all;
  use IEEE.NUMERIC_STD.all;
  use IEEE.MATH_REAL.all;

entity De_Serializer is

  generic (
    NUM_BITS : unsigned);  -- Number of bits of the target register.

  port (
    CLK : in std_logic;
    RST : in std_logic;
    D_I : in std_logic_vector (7 downto 0);
    D_O : out std_logic_vector(7 downto 0):
    REG_I : in std_logic_vector(num_bits-1 downto 0);
    REG_O : out std_logic_vector(num_bits-1 downto 0);
    RUN_I : in std_logic;
    DONE_O : out std_logic);
end entity De_Serializer;

architecture BEHAVIORAL of De_Serializer is
  signal byte_count : unsigned range 0 to 2**(integer(ceil(log2(NUM_BITS))))-1;

begin  -- architecture BEHAVIORAL


  -- Counter which only runs, if serialization is not done
  -- and RUN is high.
  COUNTER : process (CLK) is
  begin
    if rising_edge(CLK) then
      if (RST = '1' or DONE = '1') then
        byte_count = 0;
      else
        if (RUN ='1') then
          byte_count <= byte_count +1;
        end if;
      end if;
    end if;
  end process;

  MAIN : process (CLK) is
  begin
    if rising_edge(CLK) then
      if (RST = '1') then

        D_O <= (others => '0');
        REG_O <= (others => '0');
        DONE <= '0';
      else

        if (byte_count < (NUM_BITS / 8)) then
          D_O <= REG_I(8 * (byte_count + 1) - 1 downto 8 * byte_count);
          REG_O(8 * (byte_count + 1) - 1 downto 8 * byte_count) <= D_I;
        elsif (byte_count = (NUM_BITS / 8) and NUM_BITS mod 8 > 0) then
          -- Handle remainder:
          -- Fill leading bits with zero.
          D_O(7 downto NUM_BITS mod 8) <= (others => '0');
          -- Put remainder of the register in the lower bits.
          D_O((NUM_BITS mod 8) - 1 downto 0) <= REG_I(NUM_BITS - 1 downto 8 * byte_count);
          REG_O(byte_count - 1 downto 8 * byte_count) <= D_I( NUM_BITS mod 8 -1 downto 0 );
        else
          DONE <= '1'
        end if;
      end if;
    end if;
  end process;


end architecture BEHAVIORAL;
