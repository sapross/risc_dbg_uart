-------------------------------------------------
-- Author: Stephan Proß
--
-- Create Date: 03/08/2022 02:46:11 PM
-- Design Name:
-- Module Name: TB_UART - Behavioral
-- Project Name: UART-DTM
-- Tool Versions: Vivado 2021.2
-- Description: Simulation testing functionality of UART communication interface.
----------------------------------------------------------------------------------

library IEEE;
  use IEEE.STD_LOGIC_1164.all;
  use IEEE.NUMERIC_STD.all;
  use IEEE.MATH_REAL.uniform;
  use IEEE.MATH_REAL.floor;

entity TB_UART is
end entity TB_UART;

architecture TB of TB_UART is

  constant BAUD_RATE   : integer := 3 * 10 ** 6;    -- Hz
  constant BAUD_PERIOD : time    := 333 ns;         -- ns;
  constant CLK_RATE    : integer := 100 * 10 ** 6;  -- Hz
  constant CLK_PERIOD  : time    := 10 ns;          -- ns;

  signal clk           : std_logic;
  signal rst_i         : std_logic;

  signal rxd           : std_logic;
  signal txd           : std_logic;

  signal din, dout     : std_logic_vector(7 downto 0);

  procedure uart_transmit (
    constant word :     std_logic_vector(7 downto 0);
    signal txd_i  : out std_logic
  ) is

    variable seed1, seed2 : positive := 1;
    variable x            : real;
    variable delay        : integer;
    constant JITTER       : real     := 0.30;

  begin

    -- Start bit.
    txd_i <= '0';
    uniform(seed1, seed2, x);
    delay := integer(floor(x * 333.0 * JITTER * 10.0 ** 3));
    wait for delay * ps;
    wait for BAUD_PERIOD - BAUD_PERIOD * JITTER * 0.5;

    -- Serialize word into txd_i.
    for i in 0 to 7 loop

      txd_i <= word(i);
      uniform(seed1, seed2, x);
      delay := integer(floor(x * 333.0 * JITTER * 10.0 ** 3));
      wait for delay * ps;
      wait for BAUD_PERIOD - BAUD_PERIOD * JITTER * 0.5;

    end loop;

    -- Stop bit.
    txd_i <= '1';
    uniform(seed1, seed2, x);
    delay := integer(floor(x * 333.0 * JITTER * 10.0 ** 3));
    wait for delay * ps;
    wait for BAUD_PERIOD - BAUD_PERIOD * JITTER * 0.5;

  end procedure uart_transmit;

  procedure uart_receive (
    signal word  : out std_logic_vector(7 downto 0);
    signal rxd_i : in  std_logic
  ) is
  begin

    -- Wait until start bit is received.
    while rxd_i = '1' loop

      wait for CLK_PERIOD;

    end loop;

    -- Skip the start bit.
    wait for BAUD_PERIOD;
    -- Deserialize data from rxd_i.
    for i in 0 to 7 loop

      word(i) <= rxd_i;
      wait for BAUD_PERIOD;

    end loop;

    -- Wait for stop bit.
    wait for BAUD_PERIOD;

  end procedure uart_receive;

begin

  CLK_PROCESS : process is
  begin

    clk <= '0';
    wait for CLK_PERIOD / 2;
    clk <= '1';
    wait for CLK_PERIOD / 2;

  end process CLK_PROCESS;

  MAIN : process is

    variable seed1, seed2 : positive := 1;
    variable x            : real;
    variable delay        : integer;

  begin

    wait for 1 ps;
    rst_i <= '1';
    rxd   <= '1';
    wait for CLK_PERIOD;
    rst_i <= '0';
    wait for 10 * CLK_PERIOD;

    din <= x"FA";
    wait for CLK_PERIOD;

    while true loop

      uniform(seed1, seed2, x);
      delay := integer(floor(x * 333.0 * 10.0 ** 3));
      wait for delay * ps;
      uart_transmit(din, rxd);

    end loop;

    wait;

  end process MAIN;

  RECEIVE : process is
  begin

    while true loop

      uart_receive(dout, txd);

    end loop;

    wait;

  end process RECEIVE;

  DUT : entity work.uart_top
    generic map (
      CLK_RATE  => CLK_RATE,
      BAUD_RATE => BAUD_RATE
    )
    port map (
      CLK => clk,
      RSTN => not rst_i,
      RXD_DEBUG => rxd,
      TXD_DEBUG => txd
    );

end architecture TB;
