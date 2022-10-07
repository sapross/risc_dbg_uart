----------------------------------------------------------------------------------
-- Company:
-- Engineer:
--
-- Create Date:    12:15:23 07/27/2017
-- Design Name:
-- Module Name:    uart - Behavioral
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
  use IEEE.STD_LOGIC_1164.all;
  use IEEE.NUMERIC_STD.all;
  use work.baudPack.all;

entity UART is
  generic (
    CLK_RATE  : integer;
    BAUD_RATE : integer
  );
  port (
    CLK        : in    std_logic;
    RST        : in    std_logic;
    RE_I       : in    std_logic;
    WE_I       : in    std_logic;
    RX_I       : in    std_logic;
    TX_O       : out   std_logic;
    TX_READY_O : out   std_logic;
    RX_EMPTY_O : out   std_logic;
    RX_FULL_O  : out   std_logic;
    DSEND_I    : in    std_logic_vector(7 downto 0);
    DREC_O     : out   std_logic_vector(7 downto 0)
  );
end entity UART;

architecture BEHAVIORAL of UART is

  signal rst_n            : std_logic;

  signal baudtick         : std_logic;
  signal tx_start         : std_logic;
  signal rx_rd,  rx_wr    : std_logic;
  signal tx_rd,  tx_wr    : std_logic;
  signal rx_din, rx_dout  : std_logic_vector(7 downto 0);
  signal tx_din, tx_dout  : std_logic_vector(7 downto 0);
  signal tx_full          : std_logic;
  signal tx_empty         : std_logic;

begin

  rst_n    <= not RST;
  tx_start <= not tx_empty;

  BAUDGEN_1 : entity work.baudgen
    generic map (
      BDDIVIDER => bdDiv(CLK_RATE, BAUD_RATE)
    )
    port map (
      CLK      => CLK,
      RST      => RST,
      BAUDTICK => baudtick
    );

  FRX : entity work.fifo
    port map (
      CLK    => CLK,
      RST    => RST,
      RD     => rx_rd,
      WR     => rx_wr,
      W_DATA => rx_din,
      R_DATA => rx_dout,
      EMPTY  => RX_EMPTY_O,
      FULL   => RX_FULL_O
    );

  FTX : entity work.fifo
    port map (
      CLK    => CLK,
      RST    => RST,
      RD     => tx_rd,
      WR     => WE_I,
      W_DATA => DSEND_I,
      R_DATA => tx_dout,
      EMPTY  => tx_empty,
      FULL   => tx_full
    );

  URX : entity work.uart_rx
    generic map (
      OVERSAMPLING => ovSamp(CLK_RATE)
    )
    port map (
      CLK     => CLK,
      RST     => RST,
      B_TICK  => baudtick,
      RX      => RX_I,
      RX_DONE => rx_wr,
      RX_BRK  => open,
      DOUT    => rx_din
    );

  UTX : entity work.uart_tx
    generic map (
      OVERSAMPLING => ovSamp(CLK_RATE)
    )
    port map (
      CLK      => CLK,
      RESETN   => rst_n,
      B_TICK   => baudtick,
      TX       => TX_O,
      TX_START => tx_start,
      TX_DONE  => tx_rd,
      D_IN     => tx_dout
    );

  TX_READY : process(CLK) is
  begin
    if ( rising_edge(CLK)) then
      if tx_full = '0' and WE_I = '0' and RST ='0' then
        TX_READY_O <= '1';
      else
        TX_READY_O <= '0';
      end if;
    end if;
  end process TX_READY;

  WRITE : process is
  begin

    wait until rising_edge(CLK);

    if (RST = '1') then
      tx_wr <= '0';
    else
      tx_wr <= '0';
      if (WE_I = '1') then
        tx_wr <= '1';
      end if;
    end if;

  end process WRITE;

  READ : process (RE_I, rx_dout) is
  begin

    DREC_O <= (others => '0');
    rx_rd  <= '0';

    if (RE_I = '1') then
      DREC_O <= rx_dout;
      rx_rd  <= '1';
    end if;

  end process READ;

end architecture BEHAVIORAL;
