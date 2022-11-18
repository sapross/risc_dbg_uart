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
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library WORK;
  use work.uart_pkg_vhdl.all;
  use work.dm.all;

entity TB_UART_DMI is
end entity TB_UART_DMI;

architecture TB of TB_UART_DMI is

  constant clk_rate                     : integer := 100 * 10 ** 6;  -- Hz
  constant clk_period                   : time    := 10 ns;          -- ns;
  constant baud_rate                    : integer := 3 * 10 ** 6;    -- Hz
  constant baud_period                  : time    := 333 ns;         -- ns;

  signal clk                            : std_logic;
  signal rst                            : std_logic;
  signal rst_n                          : std_logic;

  signal tap_read                       : std_logic;
  signal tap_write                      : std_logic;
  signal dmi_tap                        : std_logic_vector(DMI_REQ_LENGTH - 1 downto 0);
  signal dmi                            : std_logic_vector(DMI_REQ_LENGTH - 1 downto 0);
  signal dmi_dm                         : std_logic_vector(DMI_REQ_LENGTH - 1 downto 0);
  signal done                           : std_logic;
  signal dmi_hard_reset                 : std_logic;

  signal dmi_resp_valid                 : std_logic;
  signal dmi_resp_ready                 : std_logic;
  signal dmi_resp                       : std_logic_vector(DMI_RESP_LENGTH - 1 downto 0);

  signal dmi_req_valid                  : std_logic;
  signal dmi_req_ready                  : std_logic;
  signal dmi_req                        : std_logic_vector(DMI_REQ_LENGTH - 1 downto 0);

  signal dmi_reset                      : std_logic;

begin

  rst_n <= not rst;

  DMI_UART_1 : entity work.dmi_uart
    port map (
      CLK_I  => clk,
      RST_NI => rst_n,

      TAP_READ_I       => tap_read,
      TAP_WRITE_I      => tap_write,
      DMI_I            => dmi,
      DMI_O            => dmi_tap,
      DONE_O           => done,
      DMI_HARD_RESET_I => dmi_hard_reset,

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
    wait for clk_period / 2;
    clk <= '1';
    wait for clk_period / 2;

  end process CLK_PROCESS;

  DMI_ECHO : process is
  begin

    wait for 1 ps;
    dmi_dm        <= (others => '0');
    dmi_resp      <= (others => '0');
    dmi_req_ready <= '0';
    wait for 2 * clk_period;

    while (true) loop

      if (dmi_resp_ready = '1') then
        dmi_resp       <= dmi_dm(dmi_resp'length - 1 downto 0);
        dmi_resp_valid <= '1';
      else
        dmi_resp_valid <= '0';
      end if;

      if (dmi_req_valid = '1') then
        dmi_dm        <= dmi_req;
        dmi_req_ready <= '1';
      else
        dmi_req_ready <= '0';
      end if;

      wait for clk_period;

    end loop;

    wait;

  end process DMI_ECHO;

  MAIN : process is
  begin

    rst            <= '1';
    tap_read       <= '0';
    tap_write      <= '0';
    dmi_hard_reset <= '0';
    wait for clk_period;
    rst            <= '0';
    wait for 2 * clk_period;

    dmi(dmi'Length - 1 downto 34) <= (others => '1');
    dmi(33 downto 32)             <= DTM_READ;
    dmi(31 downto 0)              <= (others => '1');
    tap_write                     <= '1';

    while done = '0' loop

      wait for clk_period;

    end loop;

    tap_write <= '0';
    wait for clk_period;
    tap_read  <= '1';

    while done = '0' loop

      wait for clk_period;

    end loop;

    dmi            <= dmi_tap;
    tap_read       <= '0';
    wait for clk_period * 2;
    dmi_hard_reset <= '1';
    wait for clk_period;
    dmi_hard_reset <= '0';
    wait;

  end process MAIN;

end architecture TB;
