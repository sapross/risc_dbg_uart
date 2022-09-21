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

  constant BAUD_RATE     : integer := 3 * 10 ** 6;    -- Hz
  constant BAUD_PERIOD   : time    := 333 ns;         -- ns;
  constant CLK_RATE      : integer := 100 * 10 ** 6;  -- Hz
  constant CLK_PERIOD    : time    := 10 ns;          -- ns;

  -- Simulates receiving a byte from UART-Interface.

  procedure rec_byte (
    constant data     : std_logic_vector( 7 downto 0);
    signal drec_i     : out std_logic_vector(7 downto 0);
    signal rx_empty_i : out std_logic;
    signal re_i       : in std_logic)
  is
  begin
    report "Sending byte";
    rx_empty_i <= '0';
    drec_i     <= (others => '0');

    while (re_i = '0') loop

      wait for CLK_PERIOD;

    end loop;
    drec_i <= data;
    rx_empty_i <= '1';
  end procedure rec_byte;

  -- Simulates a write to DMI-Interface

  procedure write_dmi (
    signal dmi_i     : out std_logic_vector(DMI_REQ_LENGTH - 1 downto 0);
    signal dmi_req_i : in dmi_req_t;
    signal ready     : out std_logic;
    signal valid     : in std_logic
  )
  is
  begin
    report "Writing to dmi";
    ready <= '1';
    while (valid = '0') loop

      wait for CLK_PERIOD;

    end loop;

    dmi_i <= dmi_req_to_stl(dmi_req_i);
    wait for CLK_PERIOD;

  end procedure write_dmi;

  -- Simulates a read from the DMI-Interace.

  procedure read_dmi (
    signal dmi_i      : in std_logic_vector(DMI_REQ_LENGTH - 1 downto 0);
    signal dmi_resp_i : out dmi_resp_t;
    signal ready      : in std_logic;
    signal valid      : out std_logic
  ) is
  begin
    report "Reading from dmi";
    dmi_resp_i <= stl_to_dmi_resp(dmi_i);
    valid      <= '1';
    while (ready = '0') loop

      wait for CLK_PERIOD;

    end loop;

    wait for CLK_PERIOD;

  end procedure;

  signal clk             : std_logic;
  signal rst             : std_logic;

  signal we              : std_logic;
  signal re              : std_logic;
  signal tx_ready        : std_logic;
  signal rx_empty        : std_logic;
  signal rx_full         : std_logic;
  signal dsend           : std_logic_vector(7 downto 0);
  signal drec            : std_logic_vector(7 downto 0);

  signal dtmcs_select    : std_logic;
  signal dmi_reset       : std_logic;
  signal dmi_error       : std_logic_vector(1 downto 0);
  signal dmi_write_ready : std_logic;
  signal dmi_write_valid : std_logic;
  signal dmi_write       : dmi_req_t;
  signal dmi_read_ready  : std_logic;
  signal dmi_read_valid  : std_logic;
  signal dmi_read        : dmi_resp_t;

  signal dmi             : std_logic_vector(DMI_REQ_LENGTH - 1 downto 0);

begin

  DUT : entity work.dmi_uart_tap
    generic map (
      CLK_RATE  => CLK_RATE,
      BAUD_RATE => BAUD_RATE
    )
    port map (
      CLK               => clk,
      RST               => rst,
      RE_O              => re,
      WE_O              => we,
      TX_READY_I        => tx_ready,
      RX_EMPTY_I        => rx_empty,
      RX_FULL_I         => rx_full,
      DSEND_O           => dsend,
      DREC_I            => drec,
      DTMCS_SELECT_O    => dtmcs_select,
      DMI_RESET_O       => dmi_reset,
      DMI_ERROR_I       => dmi_error,
      DMI_WRITE_READY_I => dmi_write_ready,
      DMI_WRITE_VALID_O => dmi_write_valid,
      DMI_WRITE_O       => dmi_write,
      DMI_READ_READY_O  => dmi_read_ready,
      DMI_READ_VALID_I  => dmi_read_valid,
      DMI_READ_I        => dmi_read
    );

  CLK_PROCESS : process is
  begin

    clk <= '0';
    wait for CLK_PERIOD / 2;
    clk <= '1';
    wait for CLK_PERIOD / 2;

  end process CLK_PROCESS;

  MAIN : process is
  begin

    --wait for 1 ps;
    rst <= '1';
    drec <= (others => '0');
    tx_ready <= '1';
    rx_empty <= '0';
    rx_full <= '0';
    wait for CLK_PERIOD;
    rst <= '0';
    wait for 2 * CLK_PERIOD;

    -- Testing Read from IDCODE
    rec_byte (
        data       => HEADER,
        drec_i     => drec,
        rx_empty_i => rx_empty,
        re_i       => re);
    wait for CLK_PERIOD;
    rec_byte (
        data       => CMD_READ & "00000" or X"01",
        drec_i     => drec,
        rx_empty_i => rx_empty,
        re_i       => re);
    wait for CLK_PERIOD;
    -- Length of IDCODE register is 4 bytes.
    rec_byte (
        data       => std_logic_vector(to_unsigned(4,8)),
        drec_i     => drec,
        rx_empty_i => rx_empty,
        re_i       => re);
    wait for CLK_PERIOD;

    -- Testing Read from dtmcs
    rec_byte (
        data       => HEADER,
        drec_i     => drec,
        rx_empty_i => rx_empty,
        re_i       => re);
    wait for CLK_PERIOD;
    rec_byte (
        data       => CMD_READ & "00000" or X"10",
        drec_i     => drec,
        rx_empty_i => rx_empty,
        re_i       => re);
    wait for CLK_PERIOD;
    -- Length of DTMCS register is 4 bytes.
    rec_byte (
        data       => std_logic_vector(to_unsigned(4,8)),
        drec_i     => drec,
        rx_empty_i => rx_empty,
        re_i       => re);
    wait for CLK_PERIOD;

    -- Testing write to dmi
    rec_byte (
        data       => HEADER,
        drec_i     => drec,
        rx_empty_i => rx_empty,
        re_i       => re);
    wait for CLK_PERIOD;
    rec_byte (
        data       => CMD_WRITE & "00000" or X"11",
        drec_i     => drec,
        rx_empty_i => rx_empty,
        re_i       => re);
    wait for CLK_PERIOD;
    -- Length of a dmi request is 41 bits -> 6 byte.
    rec_byte (
        data       => std_logic_vector(to_unsigned(6,8)),
        drec_i     => drec,
        rx_empty_i => rx_empty,
        re_i       => re);
    wait for CLK_PERIOD;

    rec_byte (
        data       => X"12",
        drec_i     => drec,
        rx_empty_i => rx_empty,
        re_i       => re);
    wait for CLK_PERIOD;
    rec_byte (
        data       => X"34",
        drec_i     => drec,
        rx_empty_i => rx_empty,
        re_i       => re);
    wait for CLK_PERIOD;
    rec_byte (
        data       => X"56",
        drec_i     => drec,
        rx_empty_i => rx_empty,
        re_i       => re);
    wait for CLK_PERIOD;
    rec_byte (
        data       => X"78",
        drec_i     => drec,
        rx_empty_i => rx_empty,
        re_i       => re);
    wait for CLK_PERIOD;
    rec_byte (
        data       => X"9A",
        drec_i     => drec,
        rx_empty_i => rx_empty,
        re_i       => re);
    wait for CLK_PERIOD;
    rec_byte (
        data       => X"BC",
        drec_i     => drec,
        rx_empty_i => rx_empty,
        re_i       => re);
    wait for CLK_PERIOD;

    -- Testing read from dmi
    rec_byte (
        data       => HEADER,
        drec_i     => drec,
        rx_empty_i => rx_empty,
        re_i       => re);
    wait for CLK_PERIOD;
    rec_byte (
        data       => CMD_READ & "00000" or X"11",
        drec_i     => drec,
        rx_empty_i => rx_empty,
        re_i       => re);
    wait for CLK_PERIOD;
    -- Length of a dmi response is 34 bits -> 5 byte.
    rec_byte (
        data       => std_logic_vector(to_unsigned(5,8)),
        drec_i     => drec,
        rx_empty_i => rx_empty,
        re_i       => re);
    wait for CLK_PERIOD;

    wait;

  end process MAIN;

  DMI_ECHO : process is
  begin

    wait for 1 ps;
    dmi <= (others => '0');
    dmi_error <= (others => '0');
    dmi_write_ready <= '0';
    dmi_read_valid <= '0';
    dmi_read <= (data => (others => '0'), resp => (others => '0'));
    wait for 2 * CLK_PERIOD;

    while (true) loop

      if (dmi_read_ready = '1') then
        read_dmi (
          dmi_i      => dmi,
          dmi_resp_i => dmi_read,
          ready      => dmi_read_ready,
          valid      => dmi_read_valid);
      elsif (dmi_write_valid = '1') then
        write_dmi (
          dmi_i     => dmi,
          dmi_req_i => dmi_write,
          ready     => dmi_write_ready,
          valid     => dmi_write_valid);
      end if;
      wait for CLK_PERIOD;
    end loop;
    wait;
  end process DMI_ECHO;

end architecture TB;
