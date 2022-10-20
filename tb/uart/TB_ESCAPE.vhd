-------------------------------------------------
-- Author: Stephan Proß
--
-- Create Date: 03/08/2022 02:46:11 PM
-- Design Name:
-- Module Name: TB_ESCAPE - Behavioral
-- Project Name: UART-DTM
-- Tool Versions: Vivado 2021.2
-- Description: Simulation testing functionality of escape filter.
----------------------------------------------------------------------------------

library IEEE;
  use IEEE.STD_LOGIC_1164.all;
  use IEEE.NUMERIC_STD.all;
  use IEEE.MATH_REAL.uniform;
  use IEEE.MATH_REAL.floor;

entity TB_ESCAPE is
end entity TB_ESCAPE;

architecture TB of TB_ESCAPE is

  constant BAUD_RATE      : integer := 3 * 10 ** 6;    -- Hz
  constant BAUD_PERIOD    : time    := 333 ns;         -- ns;
  constant CLK_RATE       : integer := 100 * 10 ** 6;  -- Hz
  constant CLK_PERIOD     : time    := 10 ns;          -- ns;

  signal clk              : std_logic;
  signal rst_i            : std_logic;

  signal rx_drec          : std_logic_vector( 7 downto 0);
  signal rx_empty         : std_logic;
  signal rx_re            : std_logic;

  signal esc_drec         : std_logic_vector( 7 downto 0);
  signal valid            : std_logic;
  signal esc              : std_logic;
  signal re               : std_logic;

begin

  DUT : entity work.escape
    port map (
      CLK        => clk,
      RST       => rst_i,
      RX_RE_O    => rx_re,
      DREC_I     => rx_drec,
      RX_EMPTY_I => rx_empty,
      DREC_O     => esc_drec,
      VALID_O    => valid,
      ESC_O      => esc,
      RE_I       => re
    );

  CLK_PROCESS : process is
  begin

    clk <= '0';
    wait for CLK_PERIOD / 2;
    clk <= '1';
    wait for CLK_PERIOD / 2;

  end process CLK_PROCESS;

  MAIN : process is

  begin

    wait for 1 ps;
    rst_i    <= '1';
    rx_empty <= '1';
    rx_drec  <= (others => '0');
    re       <= '0';
    wait for CLK_PERIOD;
    rst_i    <= '0';
    wait for CLK_PERIOD;

    rx_drec  <= x"55";
    rx_empty <= '0';
    wait for CLK_PERIOD;
    rx_drec  <= x"00";
    rx_empty <= '1';
    re<= '1';
    wait for CLK_PERIOD;
    re <= '0';
    rx_drec  <= x"B1";
    rx_empty <= '0';
    wait for CLK_PERIOD;
    rx_drec  <= x"00";
    rx_empty <= '1';
    re<= '0';
    wait for CLK_PERIOD;
    rx_drec  <= x"AB";
    rx_empty <= '0';
    wait for CLK_PERIOD;
    rx_drec  <= x"00";
    rx_empty <= '1';
    re<= '1';
    wait;

  end process MAIN;

end architecture TB;
