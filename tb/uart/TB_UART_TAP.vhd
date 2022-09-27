---------------------
-- Author: Stephan Proß
--
-- Create Date: 03/08/2022 02:46:11 PM
-- Design Name:
-- Module Name: TB_UART_TAP - Behavioral
-- Project Name: UART-DTM
-- Tool Versions: Vivado 2021.2
-- Description: Simulation testing functionality of UART Test Access Point.
----------------------------------------------------------------------------------

library IEEE;
  use IEEE.STD_LOGIC_1164.all;
  use IEEE.NUMERIC_STD.all;
  use IEEE.MATH_REAL.uniform;
  use IEEE.MATH_REAL.floor;

library WORK;
  use WORK.uart_pkg.all;

entity TB_UART_TAP is
end entity TB_UART_TAP;

architecture TB of TB_UART_TAP is

  constant BAUD_RATE               : integer := 3 * 10 ** 6;    -- Hz
  constant BAUD_PERIOD             : time    := 333 ns;         -- ns;
  constant CLK_RATE                : integer := 100 * 10 ** 6;  -- Hz
  constant CLK_PERIOD              : time    := 10 ns;          -- ns;

  -- Simulates receiving a byte from UART-Interface.

  procedure rec_byte (
    constant data     : std_logic_vector( 7 downto 0);
    signal drec_i     : out std_logic_vector(7 downto 0);
    signal rx_empty_i : out std_logic;
    signal re_i       : in std_logic)
  is
  begin

    -- report "Sending byte";
    rx_empty_i <= '0';
    drec_i     <= (others => '0');
    while (re_i = '0') loop
      wait for CLK_PERIOD;
    end loop;

    if (re_i = '1') then
      drec_i <= data;
      wait for CLK_PERIOD;
    else
      end if;

  end procedure rec_byte;

  -- Simulates the behavior of the dmi_handler

  procedure dmi_handler (
    signal read_i    : in std_logic;
    signal write_i   : in std_logic;
    signal dmi_o     : out std_logic_vector(DMI_REQ_LENGTH - 1 downto 0);
    signal dmi_i     : in std_logic_vector(DMI_REQ_LENGTH - 1 downto 0);
    signal local_dmi : inout std_logic_vector(DMI_REQ_LENGTH - 1 downto 0);
    signal done_o    : out std_logic
  )
  is
  begin
    if (read_i = '1' or write_i = '1') then

      if (read_i = '1' and write_i = '0') then
        dmi_o <= local_dmi;
      elsif (read_i = '0' and write_i = '1') then
        local_dmi <= dmi_i;
      elsif (read_i = '1' and write_i = '1') then
        dmi_o     <= local_dmi;
        local_dmi <= dmi_i;
      end if;

      wait for CLK_PERIOD;
      done_o <= '1';
      wait for CLK_PERIOD;

      while (read_i = '1' or write_i ='1') loop

        wait for CLK_PERIOD;

      end loop;

      done_o <= '0';
    else
      wait for CLK_PERIOD;
    end if;

  end procedure dmi_handler;

  signal clk                       : std_logic;
  signal rst                       : std_logic;

  signal we                        : std_logic;
  signal re                        : std_logic;
  signal tx_ready                  : std_logic;
  signal rx_empty                  : std_logic;
  signal rx_full                   : std_logic;
  signal dsend                     : std_logic_vector(7 downto 0);
  signal drec                      : std_logic_vector(7 downto 0);

  signal dtmcs_select              : std_logic;
  signal dmi_reset                 : std_logic;
  signal dmi_error                 : std_logic_vector(1 downto 0);
  signal dmi_read                  : std_logic;
  signal dmi_write                 : std_logic;
  signal tap_dmi                   : std_logic_vector(DMI_REQ_LENGTH - 1 downto 0);
  signal handler_dmi               : std_logic_vector(DMI_REQ_LENGTH - 1 downto 0);
  signal local_dmi                 : std_logic_vector(DMI_REQ_LENGTH - 1 downto 0);
  signal done                      : std_logic;

begin

  DUT : entity work.dmi_uart_tap
    generic map (
      CLK_RATE  => CLK_RATE,
      BAUD_RATE => BAUD_RATE
    )
    port map (
      CLK            => clk,
      RST            => rst,
      RE_O           => re,
      WE_O           => we,
      TX_READY_I     => tx_ready,
      RX_EMPTY_I     => rx_empty,
      RX_FULL_I      => rx_full,
      DSEND_O        => dsend,
      DREC_I         => drec,
      DTMCS_SELECT_O => dtmcs_select,
      DMI_RESET_O    => dmi_reset,
      DMI_ERROR_I    => dmi_error,
      DMI_READ_O     => dmi_read,
      DMI_WRITE_O    => dmi_write,
      DMI_O          => tap_dmi,
      DMI_I          => handler_dmi,
      DMI_DONE_I         => done
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
    local_dmi   <= (others => '0');
    handler_dmi <= (others => '0');
    dmi_error   <= (others => '0');
    dmi_write   <= '0';
    dmi_read    <= '0';
    done        <= '0';
    wait for 2 * CLK_PERIOD;

    while (true) loop

      dmi_handler (
          read_i    => dmi_read,
          write_i   => dmi_write,
          dmi_i     => tap_dmi,
          dmi_o     => handler_dmi,
          local_dmi => local_dmi,
          done_o    => done
          );
      -- wait for CLK_PERIOD;

    end loop;

    wait;

  end process DMI_ECHO;
  MAIN : process is
  begin

    wait for 1 ps;
    rst      <= '1';
    drec     <= (others => '0');
    tx_ready <= '1';
    rx_empty <= '1';
    rx_full  <= '0';
    wait for CLK_PERIOD;
    rst      <= '0';
    wait for 2 * CLK_PERIOD;

    -- Testing Read from IDCODE
    rec_byte (
        data       => HEADER,
        drec_i     => drec,
        rx_empty_i => rx_empty,
        re_i       => re);
    rec_byte (
        data       => CMD_READ & ADDR_IDCODE,
        drec_i     => drec,
        rx_empty_i => rx_empty,
        re_i       => re);
    -- Length of IDCODE register is 4 bytes.
    rec_byte (
        data       => std_logic_vector(to_unsigned(4,8)),
        drec_i     => drec,
        rx_empty_i => rx_empty,
        re_i       => re);

    -- Testing Read from dtmcs
    rec_byte (
        data       => HEADER,
        drec_i     => drec,
        rx_empty_i => rx_empty,
        re_i       => re);
    rec_byte (
        data       => CMD_READ & ADDR_DTMCS,
        drec_i     => drec,
        rx_empty_i => rx_empty,
        re_i       => re);
    -- Length of DTMCS register is 4 bytes.
    rec_byte (
        data       => std_logic_vector(to_unsigned(4,8)),
        drec_i     => drec,
        rx_empty_i => rx_empty,
        re_i       => re);

    -- Testing write to dmi
    rec_byte (
        data       => HEADER,
        drec_i     => drec,
        rx_empty_i => rx_empty,
        re_i       => re);
    rec_byte (
        data       => CMD_WRITE & ADDR_DMI,
        drec_i     => drec,
        rx_empty_i => rx_empty,
        re_i       => re);
    -- Length of a dmi request is 41 bits -> 6 byte.
    rec_byte (
        data       => std_logic_vector(to_unsigned(6,8)),
        drec_i     => drec,
        rx_empty_i => rx_empty,
        re_i       => re);

    rec_byte (
        data       => X"12",
        drec_i     => drec,
        rx_empty_i => rx_empty,
        re_i       => re);
    rec_byte (
        data       => X"34",
        drec_i     => drec,
        rx_empty_i => rx_empty,
        re_i       => re);
    rec_byte (
        data       => X"56",
        drec_i     => drec,
        rx_empty_i => rx_empty,
        re_i       => re);
    rec_byte (
        data       => X"78",
        drec_i     => drec,
        rx_empty_i => rx_empty,
        re_i       => re);
    rec_byte (
        data       => X"9A",
        drec_i     => drec,
        rx_empty_i => rx_empty,
        re_i       => re);
    rec_byte (
        data       => X"BC",
        drec_i     => drec,
        rx_empty_i => rx_empty,
        re_i       => re);

    -- Testing read from dmi
    rec_byte (
        data       => HEADER,
        drec_i     => drec,
        rx_empty_i => rx_empty,
        re_i       => re);
    rec_byte (
        data       => CMD_READ & ADDR_DMI,
        drec_i     => drec,
        rx_empty_i => rx_empty,
        re_i       => re);
    -- Length of a dmi response is 34 bits -> 5 byte.
    rec_byte (
        data       => std_logic_vector(to_unsigned(5,8)),
        drec_i     => drec,
        rx_empty_i => rx_empty,
        re_i       => re);

    wait;

  end process MAIN;


end architecture TB;
