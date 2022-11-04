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
    CLK_RATE       : integer := 25 * 10 ** 6;
    BAUD_RATE      : integer := 115200; -- 3 * 10 ** 6;
    DMI_ABITS      : integer := 5
  );
  port (
    CLK              : in    std_logic;
    -- PLL_LOCKED       : out   std_logic;
    RSTN             : in    std_logic;
    RXD_DEBUG        : in    std_logic;
    TXD_DEBUG        : out   std_logic;
    C                : out   std_logic_vector(6 downto 0);
    DP               : out   std_logic;
    AN               : out   std_logic_vector(7 downto 0);
    LED              : out   std_logic_vector(15 downto 0)
  );
end entity UART_DTM_TOP;

architecture BEHAVIORAL of UART_DTM_TOP is

  signal sys_clk                                    : std_logic;
  signal pll_locked_i                               : std_logic;
  signal rx_empty                                   : std_logic;
  signal rx_full                                    : std_logic;
  signal re,      we                                : std_logic;
  signal dsend                                      : std_logic_vector(7 downto 0);
  signal drec                                       : std_logic_vector(7 downto 0);
  signal tx_ready                                   : std_logic;
  signal dmi_tap, dmi_dm                            : std_logic_vector(DMI_REQ_LENGTH - 1 downto 0);
  signal dmi                                        : std_logic_vector(DMI_REQ_LENGTH - 1 downto 0);
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

  -- PLL_LOCKED <= pll_locked_i;
  rst        <= not RSTN or not pll_locked_i;

  CLK_WIZ_I : entity work.clk_wiz_0
    port map (
      CLK_IN1  => CLK,
      CLK_OUT1 => sys_clk,
      LOCKED   => pll_locked_i
    );

  UART_1 : entity work.uart
    generic map (
      CLK_RATE  => CLK_RATE,
      BAUD_RATE => BAUD_RATE
    )
    port map (
      CLK        => sys_clk,
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
      CLK              => sys_clk,
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
      CLK => sys_clk,
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

  DMI_REQUEST : process (sys_clk) is
  begin

    if rising_edge(sys_clk) then
      if (rst = '1') then
        dmi_req_ready  <= '0';
        dmi         <= (others => '0');
      else
        if (dmi_req_valid = '1') then
          dmi        <= dmi_req_to_stl(dmi_req);
          dmi_req_ready <= '1';
        else
          dmi_req_ready <= '0';
        end if;
      end if;
    end if;

  end process DMI_REQUEST;

  DMI_RESPONSE : process (sys_clk) is
  begin

    if rising_edge(sys_clk) then
      if (rst = '1') then
        dmi_resp_valid <= '0';
        dmi_resp.data  <= (others => '0');
        dmi_resp.resp  <= (others => '0');
      else
        if (dmi_resp_ready = '1') then
          dmi_resp       <= stl_to_dmi_resp(dmi);
          dmi_resp_valid <= '1';
        else
          dmi_resp_valid <= '0';
        end if;
      end if;
    end if;

  end process DMI_RESPONSE;

  SEGSEVEN : process (CLK) is

    variable digit     : std_logic_vector(3 downto 0);
    variable sel       : integer range 0 to 7;
    variable counter   : integer range 0 to 100000;
    -- variable s_counter : integer range 0 to CLK_RATE;
    -- variable seconds   : integer;
    variable data      : std_logic_vector(31 downto 0);

  begin

    if (rising_edge(CLK)) then
      if (rst = '1') then
        counter   := 0;
        -- s_counter := 0;
        digit     := (others => '0');
        sel       := 0;
        AN        <= (others => '0');
        C         <= (others => '1');
        DP        <= '1';
      else
        -- if (s_counter < CLK_RATE) then
        --   s_counter := s_counter + 1;
        -- else
        --   s_counter := 0;
        --   seconds   := seconds + 1;
        -- end if;
        if (counter /= 100000) then
          counter := counter + 1;
        else
          counter := 0;
          data    := stl_to_dmi_req(dmi).data;
          -- data    := std_logic_vector(to_unsigned(seconds, 32));
          digit   := data((sel + 1) * 4 - 1 downto sel * 4);
          AN      <= "11111111";
          AN(sel) <= '0';

          case digit is

            when "0000" =>
              C <= "1000000";

            when "0001" =>
              C <= "1111001";

            when "0010" =>
              C <= "0100100";

            when "0011" =>
              C <= "0110000";

            when "0100" =>
              C <= "0011001";

            when "0101" =>
              C <= "0010010";

            when "0110" =>
              C <= "0000010";

            when "0111" =>
              C <= "1111000";

            when "1000" =>
              C <= "0000000";

            when "1001" =>
              C <= "0010000";

            when "1010" =>
              C <= "0001000";

            when "1011" =>
              C <= "0000011";

            when "1100" =>
              C <= "1000110";

            when "1101" =>
              C <= "0100001";

            when "1110" =>
              C <= "0000110";

            when "1111" =>
              C <= "0001110";

            when others =>
              C <= "1111111";

          end case;

          sel := (sel + 1) mod 8;
        end if;
      end if;
    end if;

  end process SEGSEVEN;

end architecture BEHAVIORAL;
