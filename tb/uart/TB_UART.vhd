-------------------------------------------------
-- Author: Stephan Proß
--
-- Create Date: 03/08/2022 02:46:11 PM
-- Design Name:
-- Module Name: TB_UART - Behavioral
-- Project Name: UART-DTM
-- Tool Versions: Vivado 2021.2
-- Description: Simulation testing functionality of UART communication interface.
----------------------------------------------------------------------------------

library IEEE;
  use IEEE.STD_LOGIC_1164.all;
  use IEEE.NUMERIC_STD.all;
  use IEEE.MATH_REAL.uniform;
  use IEEE.MATH_REAL.floor;

entity TB_UART is
end entity TB_UART;

architecture TB of TB_UART is

  constant BAUD_RATE                     : integer := 3 * 10 ** 6;    -- Hz
  constant BAUD_PERIOD                   : time    := 333 ns;         -- ns;
  constant CLK_RATE                      : integer := 25 * 10 ** 6;   -- Hz
  constant CLK_PERIOD                    : time    := 40 ns;          -- ns;

  signal clk                             : std_logic;
  signal rst_i                           : std_logic;
  signal rst_ni                          : std_logic;

  signal rxd                             : std_logic;
  signal txd                             : std_logic;
  signal rxd2                            : std_logic;
  signal txd2                            : std_logic;
  signal sys_clk                         : std_logic;
  signal pll_locked                      : std_logic;
  signal we,           re                : std_logic;
  
  signal channel                         : std_logic;
  signal sw_channel                      : std_logic;
  
  signal tx_ready                        : std_logic;
  signal rx_empty,     rx_full           : std_logic;

  signal data_receive, data_send         : std_logic_vector(7 downto 0);
  signal din,          dout              : std_logic_vector(7 downto 0);

  constant SIM_WITH_JITTER               : boolean := false;

  procedure uart_transmit (
    constant word :     std_logic_vector(7 downto 0);
    signal txd_i  : out std_logic
  ) is

    variable seed1, seed2 : positive := 1;
    variable x            : real;
    variable delay        : integer;
    constant JITTER       : real     := 0.45;

  begin

    -- Start bit.
    txd_i <= '0';

    if (SIM_WITH_JITTER) then
      -- x is a random number between 0 and 1.
      uniform(seed1, seed2, x);
      -- delay is a random number of ns between 0 and 333*JITTER
      delay := integer(floor((0.5 - x) * 333.0 * JITTER * 10.0 ** 3));
      wait for BAUD_PERIOD + delay * ps;
    else
      wait for BAUD_PERIOD;
    end if;

    -- Serialize word into txd_i.
    for i in 0 to 7 loop

      txd_i <= word(i);

      if (SIM_WITH_JITTER) then
        uniform(seed1, seed2, x);
        delay := integer(floor((0.5 - x) * 333.0 * JITTER * 10.0 ** 3));
        wait for BAUD_PERIOD + delay * ps;
      else
        wait for BAUD_PERIOD;
      end if;

    end loop;

    -- Stop bit.
    txd_i <= '1';

    if (SIM_WITH_JITTER) then
      uniform(seed1, seed2, x);
      delay := integer(floor((0.5 - x) * 333.0 * JITTER * 10.0 ** 3));
      wait for BAUD_PERIOD + delay * ps;
    else
      wait for BAUD_PERIOD;
    end if;

  end procedure uart_transmit;

  procedure uart_receive (
    signal word  : out std_logic_vector(7 downto 0);
    signal rxd_i : in  std_logic
  ) is
  begin

    -- Wait until start bit is received.
    while rxd_i = '1' loop

      wait for CLK_PERIOD;

    end loop;

    -- Skip the start bit.
    wait for BAUD_PERIOD;
    -- Deserialize data from rxd_i.
    for i in 0 to 7 loop

      word(i) <= rxd_i;
      wait for BAUD_PERIOD;

    end loop;

    -- Wait for stop bit.
    wait for BAUD_PERIOD;

  end procedure uart_receive;

begin

  rst_ni <= not rst_i;

  CLK_PROCESS : process is
  begin

    clk <= '0';
    wait for CLK_PERIOD / 2;
    clk <= '1';
    wait for CLK_PERIOD / 2;

  end process CLK_PROCESS;

  MAIN : process is

    variable seed1, seed2 : positive := 1;
    variable x            : real;
    variable delay        : integer;

  begin

    wait for 1 ps;
    rst_i <= '1';
    rxd   <= '1';
    wait for 2* CLK_PERIOD;
    rst_i <= '0';
    wait for 10 * CLK_PERIOD;
    while pll_locked = '0' loop
      wait for CLK_PERIOD;
    end loop;

    while true loop

      uniform(seed1, seed2, x);
      din <= std_logic_vector(to_unsigned(integer(floor(x * 255.0)), 8));
      uniform(seed1, seed2, x);
      delay        := integer(floor(x * 333.0 * 10.0 ** 3));
      wait for delay * ps;
      uart_transmit(din, rxd);

    end loop;

    wait;

  end process MAIN;

  RECEIVE : process is
  begin

    while true loop

      uart_receive(dout, txd);

    end loop;

    wait;

  end process RECEIVE;

  sys_clk <= clk;

  DUT : entity work.uart
    generic map (
      CLK_RATE  => CLK_RATE,
      BAUD_RATE => BAUD_RATE
    )
    port map (
      CLK_I      => sys_clk,
      RST_NI     => rst_ni,
      RE_I       => re,
      WE_I       => we,
      RX_I       => rxd,
      TX_O       => txd,
      RX2_O       => rxd2,
      TX2_I       => txd2,
      TX_READY_O => tx_ready,
      RX_EMPTY_O => rx_empty,
      RX_FULL_O  => rx_full,
      DSEND_I    => data_send,
      DREC_O     => data_receive,
      SW_CHANNEL_I => sw_channel,
      CHANNEL_O    => channel
    );

  TRANSMIT : process (sys_clk) is
  begin

    if rising_edge(sys_clk) then
      if (rst_ni = '0') then
        data_send <= (others => '0');
        sw_channel <= '0';
        we <= '0';
        re <= '0';
      else
        if (rx_empty = '0' and dout = X"b1") then
          re <= '1';
        else
          re <= '0';
        end if;
        we <= re;
        if (re = '1' and rx_empty = '0') then
          data_send <= data_receive;
        end if;
      end if;
    end if;

  end process TRANSMIT;

end architecture TB;
