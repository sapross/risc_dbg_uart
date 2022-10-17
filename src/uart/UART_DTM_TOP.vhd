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
    CLK_RATE       : integer := 10 ** 8;
    BAUD_RATE      : integer := 3 * 10 ** 6;
    DMI_ABITS      : integer := 5
  );
  port (
    CLK              : in    std_logic;
    RSTN             : in    std_logic;
    RXD_DEBUG        : in    std_logic;
    TXD_DEBUG        : out   std_logic
  );
end entity UART_DTM_TOP;

architecture BEHAVIORAL of UART_DTM_TOP is

  signal rx_empty                                   : std_logic;
  signal rx_full                                    : std_logic;
  signal re,      we                                : std_logic;
  signal dsend                                      : std_logic_vector(7 downto 0);
  signal drec                                       : std_logic_vector(7 downto 0);
  signal tx_ready                                   : std_logic;
  signal dmi_tap, dmi_dm                            : std_logic_vector(DMI_REQ_LENGTH - 1 downto 0);
  signal rst                                        : std_logic;

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

  rst <= not RSTN;

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

      DMI_RESP_VALID_I => dmi_resp_valid,
      DMI_RESP_READY_O => dmi_resp_ready,
      DMI_RESP_I       => dmi_resp,
      DMI_REQ_VALID_O  => dmi_req_valid,
      DMI_REQ_READY_I  => dmi_req_ready,
      DMI_REQ_O        => dmi_req,

      DMI_RST_NO => dmi_reset
    );

  DMI_ECHO : process (CLK) is

    variable dmi : std_logic_vector(DMI_REQ_LENGTH - 1 downto 0);

  begin

    if rising_edge(CLK) then
      if (rst = '1') then
        dmi_resp_valid <= '0';
        dmi_resp.data  <= (others => '0');
        dmi_resp.resp  <= (others => '0');
        dmi_req_ready  <= '0';
        dmi := (others => '0');
      else
        if (dmi_req_valid = '1') then
          dmi           := dmi_req_to_stl(dmi_req);
          dmi_req_ready <= '1';
        else
          dmi_req_ready <= '0';
        end if;
        if (dmi_resp_ready = '1') then
          dmi_resp       <= stl_to_dmi_resp(dmi);
          dmi_resp_valid <= '1';
        else
          dmi_resp_valid <= '0';
        end if;
      end if;
    end if;

  end process DMI_ECHO;

end architecture BEHAVIORAL;
