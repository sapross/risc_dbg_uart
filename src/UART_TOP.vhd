---------------------------------------------------------------
-- Company:
-- Engineer:
--
-- Create Date:    12:15:23 07/27/2017
-- Design Name:
-- Module Name:    uart - Behavioral
-- Project Name:
-- Target Devices:
-- Tool versions:
-- Description:
--
-- Dependencies:
--
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
--
----------------------------------------------------------------------------------

library IEEE;
  use IEEE.STD_LOGIC_1164.ALL;

  -- Uncomment the following library declaration if using
  -- arithmetic functions with Signed or Unsigned values
  use IEEE.NUMERIC_STD.ALL;

entity UART_TOP is
  port (
    CLK      : in    std_logic;
    RST      : in    std_logic;
    RXD       : in    std_logic;
    TXD       : out   std_logic
  );
end entity UART_TOP;

architecture BEHAVIORAL of UART_TOP is

  constant HZ : integer := 100000000;

  signal tx_empty, tx_full, rx_empty, rx_full : std_logic;
  signal re,we : std_logic;
  signal din,dout : std_logic_vector (7 downto 0);

begin

  UART_1: entity work.UART
    generic map (
      HZ => HZ)
    port map (
      CLK      => CLK,
      RST      => RST,
      RE       => RE,
      WE       => WE,
      RX       => TXD,
      TX       => RXD,
      TX_EMPTY => TX_EMPTY,
      TX_FULL  => TX_FULL,
      RX_EMPTY => RX_EMPTY,
      RX_FULL  => RX_FULL,
      DIN      => DIN,
      DOUT     => DOUT);



ECHO: process (CLK) is
begin
  if rising_edge(CLK) then
    if RST = '1' then
      re <= '0';
      we <= '0';
      din <= (others => '0');
    else
      re <= '0';
      we <= '0';
      din <= (others => '0');
      if rx_empty = '0' and tx_full = '0' then
        re <= '1';
        we <= '1';
        din <= dout;
      end if;
    end if;
  end if;

end process ECHO;

end architecture BEHAVIORAL;
