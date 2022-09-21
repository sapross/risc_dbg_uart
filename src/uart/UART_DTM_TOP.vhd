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

  signal rx_empty                            : std_logic;
  signal rx_full                             : std_logic;
  signal re, we                              : std_logic;
  signal din                                 : std_logic_vector(7 downto 0);
  signal dout                                : std_logic_vector(7 downto 0);
  signal tx_ready                            : std_logic;

begin

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
      RX_FULL_O  => rx_full,
      DSEND_I    => din,
      DREC_O     => dout
    );


  -- UART_DTM_1 : entity work.dmi_uart_dtm
  --   generic map (
  --     CLK_RATE  => CLK_RATE,
  --     BAUD_RATE => BAUD_RATE,
  --     DMI_ABITS => DMI_ABITS
  --   )
  --   port map (
  --     CLK      => CLK,
  --     RST      => RST,
  --     RE       => re,
  --     WE       => we,
  --     TX_READY => tx_ready,
  --     RX_EMPTY => rx_empty,
  --     RX_FULL  => rx_full,
  --     DREC     => dout,
  --     DSEND    => din
  --   );
end architecture BEHAVIORAL;
