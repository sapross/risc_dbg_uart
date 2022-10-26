----------------------------------------------
-- Company:
-- Engineer:
--
-- Create Date:    12:15:23 07/27/2017
-- Design Name:
-- Module Name:    uart_dtm - Behavioral
-- Project Name:
-- Target Devices:
-- Tool versions:
-- Description:
-- Provides bundled interface for uart based dtm
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

entity uart_dtm is
  generic (
    CLK_RATE       : integer := 10 ** 8;
    BAUD_RATE      : integer := 115200; --3 * 10 ** 6;
    DMI_ABITS      : integer := 5
  );
  port (
    CLK              : in    std_logic;
    RST              : in    std_logic;
    RXD_DEBUG        : in    std_logic;
    TXD_DEBUG        : out   std_logic;
    DMI_REQ_VALID_O  : out   std_logic;
    DMI_REQ_READY_I  : in    std_logic;
    DMI_REQ_O        : out   dmi_req_t;
    DMI_RESP_VALID_I : in    std_logic;
    DMI_RESP_READY_O : out   std_logic;
    DMI_RESP_I       : in    dmi_resp_t

  );
end entity uart_dtm;

architecture BEHAVIORAL of uart_dtm is

  signal rx_empty                                   : std_logic;
  signal rx_full                                    : std_logic;
  signal re,      we                                : std_logic;
  signal dsend                                      : std_logic_vector(7 downto 0);
  signal drec                                       : std_logic_vector(7 downto 0);
  signal tx_ready                                   : std_logic;
  signal dmi_tap, dmi_dm                            : std_logic_vector(DMI_REQ_LENGTH - 1 downto 0);

  signal dmi_hard_reset                             : std_logic;
  signal dmi_read                                   : std_logic;
  signal dmi_write                                  : std_logic;
  signal dmi_done                                   : std_logic;

  signal dmi_resp_valid                             : std_logic;
  signal dmi_resp_ready                             : std_logic;
  signal dmi_resp                                   : dmi_resp_t;

  signal dmi_req_valid                              : std_logic;
  signal dmi_req_ready                              : std_logic;
  signal dmi_req                                    : dmi_req_t;

  signal dmi_reset                                  : std_logic;

begin

  UART_1 : entity work.uart
    generic map (
      CLK_RATE  => CLK_RATE,
      BAUD_RATE => BAUD_RATE
    )
    port map (
      CLK        => CLK,
      RST        => rst,
      RE_I       => re,
      WE_I       => we,
      RX_I       => RXD_DEBUG,
      TX_O       => TXD_DEBUG,
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
      CLK              => CLK,
      RST              => rst,
      RE_O             => re,
      WE_O             => we,
      TX_READY_I       => tx_ready,
      RX_EMPTY_I       => rx_empty,
      DSEND_O          => dsend,
      DREC_I           => drec,
      DMI_HARD_RESET_O => dmi_hard_reset,
      DMI_ERROR_I      => "00",
      DMI_READ_O       => dmi_read,
      DMI_WRITE_O      => dmi_write,
      DMI_O            => dmi_tap,
      DMI_I            => dmi_dm,
      DMI_DONE_I       => dmi_done
    );

  DMI_UART_1 : entity work.dmi_uart
    port map (
      CLK => CLK,
      RST => rst,

      TAP_READ_I       => dmi_read,
      TAP_WRITE_I      => dmi_write,
      DMI_I            => dmi_tap,
      DMI_O            => dmi_dm,
      DONE_O           => dmi_done,
      DMI_HARD_RESET_I => dmi_hard_reset,

      DMI_RESP_VALID_I => DMI_RESP_VALID_I,
      DMI_RESP_READY_O => DMI_RESP_READY_O,
      DMI_RESP_I       => DMI_RESP_I,
      DMI_REQ_VALID_O  => DMI_REQ_VALID_O,
      DMI_REQ_READY_I  => DMI_REQ_READY_I,
      DMI_REQ_O        => DMI_REQ_O,

      DMI_RST_NO => dmi_reset
    );

end architecture BEHAVIORAL;
