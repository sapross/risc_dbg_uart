---------------------
-- Author: Stephan Proß
--
-- Create Date: 03/08/2022 02:46:11 PM
-- Design Name:
-- Module Name: TB_UART_DTM - Behavioral
-- Project Name: UART-DTM
-- Tool Versions: Vivado 2021.2
-- Description: Simulation testing functionality of UART Debug Transport Module.
----------------------------------------------------------------------------------

library IEEE;
  use IEEE.STD_LOGIC_1164.all;
  use IEEE.NUMERIC_STD.all;
  use IEEE.MATH_REAL.uniform;
  use IEEE.MATH_REAL.floor;

entity TB_UART_DTM is
end entity TB_UART_DTM;

architecture TB of TB_UART_DTM is

  constant BAUD_RATE                          : integer := 3 * 10 ** 6;   -- Hz
  constant BAUD_PERIOD                        : time := 333 ns;           -- ns;
  constant CLK_RATE                           : integer := 100 * 10 ** 6; -- Hz
  constant CLK_PERIOD                         : time := 10 ns;            -- ns;

  constant DMI_ABITS                          : integer := 5;

  signal clk                                  : std_logic;
  signal rst                                  : std_logic;

  signal rxd                                  : std_logic;
  signal txd                                  : std_logic;

  signal dsend                                : std_logic_vector(7 downto 0);
  signal drec                                 : std_logic_vector(7 downto 0);

  procedure uart_transmit (
    constant word : std_logic_vector(7 downto 0);
    signal txd_i  : out std_logic
  ) is
  begin

    -- Start bit.
    txd_i <= '0';
    wait for BAUD_PERIOD;

    -- Serialize word into txd_i.
    for i in 0 to 7 loop

      txd_i <= word(i);
      wait for BAUD_PERIOD;

    end loop;

    -- Stop bit.
    txd_i <= '1';
    wait for BAUD_PERIOD;

  end procedure uart_transmit;

  procedure uart_receive (
    signal word  : out std_logic_vector(7 downto 0);
    signal rxd_i : in std_logic
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

  DUT: entity work.UART_DTM_TOP
    generic map (
      CLK_RATE  => CLK_RATE,
      BAUD_RATE => BAUD_RATE,
      DMI_ABITS => DMI_ABITS)
    port map (
      CLK => CLK,
      RST => RST,
      RXD => RXD,
      TXD => TXD);

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
