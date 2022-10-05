----------------------------------------------
-- Company:
-- Engineer:
--
-- Create Date:    12:15:23 07/27/2017
-- Design Name:
-- Module Name:    UART_DTM_TOP - Behavioral
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
  use IEEE.NUMERIC_STD.ALL;

library WORK;
  use work.uart_pkg.all;

entity UART_DTM_TOP is
  generic (
    CLK_RATE       : integer := 100000000;
    BAUD_RATE      : integer := 3 * 10 ** 6;
    DMI_ABITS      : integer := 5
  );
  port (
    CLK       : in    std_logic;
    RST       : in    std_logic;
    RXD       : in    std_logic;
    TXD       : out   std_logic
  );
end entity UART_DTM_TOP;

architecture BEHAVIORAL of UART_DTM_TOP is

  signal rx_empty                              : std_logic;
  signal rx_full                               : std_logic;
  signal re, we                                : std_logic;
  signal dsend                                 : std_logic_vector(7 downto 0);
  signal drec                                  : std_logic_vector(7 downto 0);
  signal tx_ready                              : std_logic;
  signal dmi                                   : std_logic_vector(DMI_REQ_LENGTH - 1 downto 0);

begin
  dmi <= (others => '0');
  
  UART_1 : entity work.uart
    generic map (
      CLK_RATE  => CLK_RATE,
      BAUD_RATE => BAUD_RATE
    )
    port map (
      CLK        => CLK,
      RST        => RST,
      RE_I       => re,
      WE_I       => we,
      RX_I       => RXD,
      TX_O       => TXD,
      TX_READY_O => tx_ready,
      RX_EMPTY_O => rx_empty,
      RX_FULL_O  => open,
      DSEND_I    => dsend,
      DREC_O     => drec
    );

  DMI_UART_TAP_1 : entity work.dmi_uart_tap
    generic map (
      CLK_RATE  => CLK_RATE,
      BAUD_RATE => BAUD_RATE
    )
    port map (
      CLK            => CLK,
      RST            => RST,
      RE_O           => re,
      WE_O           => we,
      TX_READY_I     => tx_ready,
      RX_EMPTY_I     => rx_empty,
      DSEND_O        => dsend,
      DREC_I         => drec,
      DTMCS_SELECT_O => open,
      DMI_RESET_O    => open,
      DMI_ERROR_I    => "00",
      DMI_READ_O     => open,
      DMI_WRITE_O    => open,
      DMI_O          => open,
      DMI_I          => dmi,
      DMI_DONE_I     => '1'
    );

end architecture BEHAVIORAL;
