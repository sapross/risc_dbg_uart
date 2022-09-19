---------------------
-- Author: Stephan Proß
--
-- Create Date: 03/08/2022 02:46:11 PM
-- Design Name:
-- Module Name: TB_UART_TAP - Behavioral
-- Project Name: UART-DTM
-- Tool Versions: Vivado 2021.2
-- Description: Simulation testing functionality of UART Test Access Point.
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;
use IEEE.MATH_REAL.uniform;
use IEEE.MATH_REAL.floor;

entity TB_UART_TAP is
end entity TB_UART_TAP;

architecture TB of TB_UART_TAP is

  constant BAUD_RATE   : integer := 3 * 10 ** 6;    -- Hz
  constant BAUD_PERIOD : time    := 333 ns;         -- ns;
  constant CLK_RATE    : integer := 100 * 10 ** 6;  -- Hz
  constant CLK_PERIOD  : time    := 10 ns;          -- ns;

  signal clk : std_logic;
  signal rst : std_logic;

  signal we       : std_logic;
  signal re       : std_logic;
  signal tx_ready : std_logic;
  signal rx_empty : std_logic;
  signal rx_full  : std_logic;
signal
  signal dsend : std_logic_vector(7 downto 0);
  signal drec  : std_logic_vector(7 downto 0);

begin
  DUT : entity work.DMI_UART_TAP
    generic map (
      CLK_RATE  => CLK_RATE,
      BAUD_RATE => BAUD_RATE)
    port map (
      CLK               => CLK,
      RST               => RST,
      --UART-Interface ports
      RE                => RE,
      WE                => WE,
      TX_READY          => TX_READY,
      RX_EMPTY          => RX_EMPTY,
      RX_FULL           => RX_FULL,
      DIN               => DIN,
      DOUT              => DOUT,
      -- DMI-Interface ports
      DTMCS_SELECT_O    => DTMCS_SELECT_O,
      DMI_RESET_O       => DMI_RESET_O,
      DMI_ERROR_I       => DMI_ERROR_I,
      DMI_WRITE_READY_I => DMI_WRITE_READY_I,
      DMI_WRITE_VALID_O => DMI_WRITE_VALID_O,
      DMI_WRITE_O       => DMI_WRITE_O,
      DMI_READ_READY_O  => DMI_READ_READY_O,
      DMI_READ_VALID_I  => DMI_READ_VALID_I,
      DMI_READ_I        => DMI_READ_I);
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
    rst <= '1';
    rxd <= '1';
    wait for CLK_PERIOD;
    rst <= '0';
    wait for CLK_PERIOD;

    -- Read IDCODE
    dsend <= X"81";
    wait for CLK_PERIOD;
    uart_transmit(dsend, rxd);

    -- READ dtmcs
    dsend <= X"90";
    wait for CLK_PERIOD;
    uart_transmit(dsend, rxd);

    -- WRITE dtmcs
    for i in 0 to (32 + 6) / 7 loop
      dsend <= X"7F";
      wait for CLK_PERIOD;
      uart_transmit(dsend, rxd);
    end loop;

    -- READ dtmcs back
    dsend <= X"90";
    wait for CLK_PERIOD;
    uart_transmit(dsend, rxd);

    -- READ dmi
    dsend <= X"91";
    wait for CLK_PERIOD;
    uart_transmit(dsend, rxd);

    -- Write dmi
    for i in 0 to (34 + DMI_ABITS + 6) / 7 loop
      dsend <= X"7F";
      wait for CLK_PERIOD;
      uart_transmit(dsend, rxd);
    end loop;

    -- READ dmi back
    dsend <= X"91";
    wait for CLK_PERIOD;
    uart_transmit(dsend, rxd);
    wait;

  end process MAIN;

  RECEIVE : process is
  begin
    wait for 3*CLK_PERIOD;
    while true loop
      uart_receive(drec, txd);
    end loop;
    wait;
  end process RECEIVE;


end architecture TB;
