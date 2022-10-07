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
use IEEE.STD_LOGIC_1164.all;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
use IEEE.NUMERIC_STD.all;

entity UART_TOP is
  generic (
    CLK_RATE  : integer := 100000000;
    BAUD_RATE : integer := 115200 --3 * 10 ** 6
    );
  port (
    CLK : in  std_logic;
    RST : in  std_logic;
    RXD : in  std_logic;
    TXD : out std_logic
    );
end entity UART_TOP;

architecture BEHAVIORAL of UART_TOP is

  signal rx_empty              : std_logic;
  signal rx_full               : std_logic;
  signal re, we                : std_logic;
  signal re_next, we_next      : std_logic;
  signal dsend                 : std_logic_vector(7 downto 0);
  signal dsend_next            : std_logic_vector(7 downto 0);
  signal drec                  : std_logic_vector(7 downto 0);
  signal tx_ready              : std_logic;
  signal counter, counter_next : integer range 0 to 255;

begin
  UART_1 : entity work.UART
    generic map (
      CLK_RATE  => CLK_RATE,
      BAUD_RATE => BAUD_RATE)
    port map (
      CLK        => CLK,
      RST        => RST,
      RE_I       => RE,
      WE_I       => WE,
      RX_I       => RXD,
      TX_O       => TXD,
      TX_READY_O => TX_READY,
      RX_EMPTY_O => RX_EMPTY,
      RX_FULL_O  => RX_FULL,
      DSEND_I    => DSEND,
      DREC_O     => DREC);


  re <= '1' when rx_empty = '0' and tx_ready = '1' else
        '0';

  ECHO : process (CLK) is
  begin

    if rising_edge(CLK) then
      if (RST = '1') then
        we    <= '0';
        dsend <= (others => '0');
        counter <= 0;
      else
        -- if (re = '1') then
          we    <= '1';
          -- dsend <= drec;
          dsend     <= std_logic_vector(to_unsigned(counter, dsend'length));
          counter <= counter + 1;
        -- else
--          we    <= '0';
--          dsend <= (others => '0');
--          counter <= counter;
--        end if;
      end if;
    end if;

  end process ECHO;

end architecture BEHAVIORAL;
