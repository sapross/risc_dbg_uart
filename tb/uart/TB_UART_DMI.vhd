---------------------
-- Author: Stephan Proß
--
-- Create Date: 03/08/2022 02:46:11 PM
-- Design Name:
-- Module Name: TB_UART_DMI - Behavioral
-- Project Name: UART-DTM
-- Tool Versions: Vivado 2021.2
-- Description: Simulation testing functionality of debug module interface
-- handler for the uart tap.
----------------------------------------------------------------------------------

library IEEE;
  use IEEE.STD_LOGIC_1164.all;
  use IEEE.NUMERIC_STD.all;

library WORK;
  use WORK.uart_pkg.all;

entity TB_UART_DMI is
end entity TB_UART_DMI;

architecture TB of TB_UART_DMI is

  constant CLK_RATE                : integer := 100 * 10 ** 6;  -- Hz
  constant CLK_PERIOD              : time    := 10 ns;          -- ns;
  constant BAUD_RATE               : integer := 3 * 10 ** 6;    -- Hz
  constant BAUD_PERIOD             : time    := 333 ns;         -- ns;

  signal clk                       : std_logic;
  signal rst                       : std_logic;

  signal tap_read                  : std_logic;
  signal tap_write                 : std_logic;
  signal dmi_tap                   : std_logic_vector(DMI_REQ_LENGTH - 1 downto 0);
  signal dmi_dm                    : std_logic_vector(DMI_REQ_LENGTH - 1 downto 0);
  signal done                      : std_logic;

  signal dmi_resp_valid            : std_logic;
  signal dmi_resp_ready            : std_logic;
  signal dmi_resp                  : dmi_resp_t;

  signal dmi_req_valid             : std_logic;
  signal dmi_req_ready             : std_logic;
  signal dmi_req                   : dmi_req_t;

  signal dmi_reset                 : std_logic;

begin

  DMI_UART_1 : entity work.dmi_uart
    port map (
      CLK => clk,
      RST => rst,

      TAP_READ_I  => tap_read,
      TAP_WRITE_I => tap_write,
      DMI_I       => dmi_dm,
      DMI_O       => dmi_tap,
      DONE_O      => done,

      DMI_RESP_VALID_I => dmi_resp_valid,
      DMI_RESP_READY_O => dmi_resp_ready,
      DMI_RESP_I       => dmi_resp,

      DMI_REQ_VALID_O => dmi_req_valid,
      DMI_REQ_READY_I => dmi_req_ready,
      DMI_REQ_O       => dmi_req,

      DMI_RST_NO => dmi_reset
    );

  CLK_PROCESS : process is
  begin

    clk <= '0';
    wait for CLK_PERIOD / 2;
    clk <= '1';
    wait for CLK_PERIOD / 2;

  end process CLK_PROCESS;

  DMI_ECHO : process is
  begin

    wait for 1 ps;
    dmi_dm         <= (others => '0');
    dmi_resp_valid <= '1';
    dmi_resp       <= '1';
    dmi_req_ready  <= '1';

    wait for 2 * CLK_PERIOD;

    while (true) loop

      if (DMI_RESP_READY_O = '1') then
        dmi_resp       <= stl_to_dmi_resp(dmi_dm);
        dmi_resp_valid <= '1';
      else
        dmi_resp       <= (others => '0');
        dmi_resp_valid <= '0';
      end if;

      if (DMI_REQ_VALID_O = '1') then
        dmi_dm        <= dmi_req_to_stl(dmi_tap);
        dmi_req_ready <= '1';
      else
        dmi_req_ready <= '0';
      end if;

      wait for CLK_PERIOD;

    end loop;

    wait;

  end process DMI_ECHO;

  MAIN : process is
  begin

    rst       <= '1';
    dmi_tap   <= (others => '0');
    tap_read  <= '0';
    tap_write <= '0';
    wait for CLK_PERIOD;
    rst       <= '0';
    wait for 2 * CLK_PERIOD;

    dmi_tap   <= (others => '1');
    tap_write <= '1';

    while done = '0' loop

      wait for CLK_PERIOD;

    end loop;

    tap_write <= '0';
    wait for CLK_PERIOD;
    tap_read  <= '1';
    dmi_tap   <= dmi_req_ready
                 
                 wait;

  end process MAIN;

end architecture TB;
