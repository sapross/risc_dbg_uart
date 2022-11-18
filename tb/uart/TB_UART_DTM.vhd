---------------------
-- Author: Stephan Proß
--
-- Create Date: 03/08/2022 02:46:11 PM
-- Design Name:
-- Module Name: TB_UART_DTM - Behavioral
-- Project Name: UART-DTM
-- Tool Versions: Vivado 2021.2
-- Description: Simulation testing functionality of UART Debug Transport
-- Module. All Components integrated.
----------------------------------------------------------------------------------

library IEEE;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library WORK;
  use work.uart_pkg_vhdl.all;
  use work.dm.all;

entity TB_UART_DTM is
end entity TB_UART_DTM;

architecture TB of TB_UART_DTM is

  constant clk_rate                                          : integer := 25 * 10 ** 6;   -- Hz
  constant clk_period                                        : time    := 40 ns;          -- ns;
  constant baud_rate                                         : integer := 3 * 10 ** 6;    -- Hz
  constant baud_period                                       : time    := 333 ns;         -- ns;

  -- Simulates receiving a byte from UART-Interface.

  procedure uart_transmit (
    constant word :    std_logic_vector;
    signal txd_i  : out std_logic
  ) is

    variable word_d : std_logic_vector(word'length -1 downto 0) := word;
    variable byte   : std_logic_vector(7 downto 0);

  begin

    -- 0 to ceil(word'length / 8) -1
    for i in 0 to (word'length + 7) / 8 - 1 loop

      if ((i + 1) * 8 > word'length) then
        byte(7 downto word'length mod 8)      := (others => '0');
        byte(word'length mod 8  - 1 downto 0) := word_d(word'length -1 downto 8 * (i));
      else
        byte := word_d(8 * (i + 1) - 1 downto (8 * i));
      end if;

      -- Start bit.
      txd_i <= '0';
      wait for baud_period;

      -- Serialize word into txd_i.
      for i in 0 to 7 loop

        txd_i <= byte(i);
        wait for baud_period;

      end loop;

      -- Stop bit.
      txd_i <= '1';
      wait for baud_period;

    end loop;

  end procedure uart_transmit;

  procedure uart_receive (
    signal word  : out std_logic_vector(7 downto 0);
    signal rxd_i : in  std_logic
  ) is

    variable byte : std_logic_vector(7 downto 0);

  begin

    -- Wait until start bit is received.
    while not rxd_i = '0' loop

      wait for clk_period;

    end loop;

    -- Skip the start bit.
    wait for 3 * baud_period / 2;
    -- Deserialize data from rxd_i.
    for i in 0 to 7 loop

      byte(i) := rxd_i;
      wait for baud_period;

    end loop;

    word <= byte;
  -- Wait for stop bit.
  -- wait for BAUD_PERIOD;

  end procedure uart_receive;

  -- Simulates the behavior of the dmi_handler

  signal clk                                                 : std_logic;
  signal rst, rst_n                                          : std_logic;

  signal rxd, txd                                            : std_logic;
  signal response                                            : std_logic_vector(7 downto 0);

  signal dmi_resp_valid                                      : std_logic;
  signal dmi_resp_ready                                      : std_logic;
  signal dmi_resp                                            : std_logic_vector(DMI_RESP_LENGTH - 1 downto 0);

  signal dmi_req_valid                                       : std_logic;
  signal dmi_req_ready                                       : std_logic;
  signal dmi_req                                             : std_logic_vector(DMI_REQ_LENGTH - 1 downto 0);

  signal dmi                                                 : std_logic_vector(DMI_REQ_LENGTH - 1 downto 0);

begin

  rst_n <= not rst;

  DUT : entity work.dtm_uart
    generic map (
      CLK_RATE  => clk_rate,
      BAUD_RATE => baud_rate
    )
    port map (
      CLK_I            => clk,
      RST_NI           => rst_n,
      DMI_RESP_VALID_I => dmi_resp_valid,
      DMI_RESP_READY_O => dmi_resp_ready,
      DMI_RESP_I       => dmi_resp,
      DMI_REQ_VALID_O  => dmi_req_valid,
      DMI_REQ_READY_I  => dmi_req_ready,
      DMI_REQ_O        => dmi_req,
      RX_I             => rxd,
      TX_O             => txd
    );

  CLK_PROCESS : process is
  begin

    clk <= '0';
    wait for clk_period / 2;
    clk <= '1';
    wait for clk_period / 2;

  end process CLK_PROCESS;

  MAIN : process is
  begin

    rst <= '1';
    rxd <= '1';
    wait for 30 * clk_period;
    rst <= '0';
    wait for 2 * clk_period;

    -- Testing Read from IDCODE
    report "Read from IDCODE";
    uart_transmit (
                   word  => HEADER,
                   txd_i => rxd);
    uart_transmit (
                   word  => CMD_READ & ADDR_IDCODE,
                   txd_i => rxd);
    -- Length of IDCODE register is 4 bytes.
    uart_transmit (
                   word  => std_logic_vector(to_unsigned(4,8)),
                   txd_i => rxd);

    report "Read from DTMCS";
    -- Testing Read from dtmcs
    uart_transmit (
                   word  => HEADER,
                   txd_i => rxd);
    uart_transmit (
                   word  => CMD_READ & ADDR_DTMCS,
                   txd_i => rxd);
    -- Length of DTMCS register is 4 bytes.
    uart_transmit (
                   word  => std_logic_vector(to_unsigned(4,8)),
                   txd_i => rxd);

    report "Write DMI write request";
    -- Testing write to dmi
    uart_transmit (
                   word  => HEADER,
                   txd_i => rxd);
    uart_transmit (
                   word  => CMD_WRITE & ADDR_DMI,
                   txd_i => rxd);
    -- Length of a dmi request is 41 bits -> 6 byte.
    uart_transmit (
                   word  => std_logic_vector(to_unsigned(6,8)),
                   txd_i => rxd);
    uart_transmit (
    -- 7b addr  &   OP      &    data
                   word  => "1111111" & DTM_WRITE & X"12345678",
                   txd_i => rxd);

    report "Write DMI read request";
    uart_transmit (
                   word  => HEADER,
                   txd_i => rxd);
    uart_transmit (
                   word  => CMD_WRITE & ADDR_DMI,
                   txd_i => rxd);
    -- Length of a dmi request is 41 bits -> 6 byte.
    uart_transmit (
                   word  => std_logic_vector(to_unsigned(6,8)),
                   txd_i => rxd);

    uart_transmit (
    -- 7b addr  &   OP      &    data
                   word  => "1111111" & DTM_READ & X"00000000",
                   txd_i => rxd);

    -- Testing read from dmi
    report "Read from DMI";
    uart_transmit (
                   word  => HEADER,
                   txd_i => rxd);
    uart_transmit (
                   word  => CMD_READ & ADDR_DMI,
                   txd_i => rxd);
    -- Length of a dmi response is 34 bits -> 5 byte.
    uart_transmit (
                   word  => std_logic_vector(to_unsigned(5,8)),
                   txd_i => rxd);

    wait;

  end process MAIN;

  RECEIVE : process is
  begin

    response <= (others => '0');
    wait for clk_period * 30;

    while true loop

      uart_receive(response, txd);

    end loop;

    wait;

  end process RECEIVE;

  DMI_REQUEST : process (clk) is
  begin

    if rising_edge(clk) then
      if (rst = '1') then
        dmi_req_ready <= '0';
        dmi           <= (others => '0');
      else
        if (dmi_req_valid = '1') then
          if (dmi_req(33 downto 32 ) = DTM_WRITE) then
            dmi <= dmi_req;
          end if;
          dmi_req_ready <= '1';
        else
          dmi_req_ready <= '0';
        end if;
      end if;
    end if;

  end process DMI_REQUEST;

  DMI_RESPONSE : process (clk) is
  begin

    if rising_edge(clk) then
      if (rst = '1') then
        dmi_resp_valid <= '0';
        dmi_resp  <= (others => '0');
      else
        if (dmi_resp_ready = '1') then
          dmi_resp       <= dmi(31 downto 0) & "00";
          dmi_resp_valid <= '1';
        else
          dmi_resp_valid <= '0';
        end if;
      end if;
    end if;

  end process DMI_RESPONSE;

end architecture TB;
