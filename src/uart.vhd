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
  use IEEE.STD_LOGIC_1164.ALL;

  -- Uncomment the following library declaration if using
  -- arithmetic functions with Signed or Unsigned values
  use IEEE.NUMERIC_STD.ALL;
  use work.baudPack.all;

entity UART is
  generic (
    HZ : integer := 30000000
  );
  port (
    CLK      : in    std_logic;
    RST      : in    std_logic;
    RE       : in    std_logic;
    WE       : in    std_logic;
    RX       : in    std_logic;
    TX       : out   std_logic;
    TX_EMPTY : out   std_logic;
    TX_FULL  : out   std_logic;
    RX_EMPTY : out   std_logic;
    RX_FULL  : out   std_logic;
    DIN      : in    std_logic_vector(7 downto 0);
    DOUT     : out   std_logic_vector(7 downto 0)
  );
end entity UART;

architecture BEHAVIORAL of UART is

  signal rst_n             : std_logic;

  signal baudtick          : std_logic;
  signal tx_start          : std_logic;
  signal rx_rd,  rx_wr     : std_logic;
  signal tx_rd,  tx_wr     : std_logic;
  signal rx_din, rx_dout   : std_logic_vector(7 downto 0);
  signal tx_din, tx_dout   : std_logic_vector(7 downto 0);

begin

  rst_n    <= not RST;
  tx_start <= not TX_EMPTY;

  BAUDGEN_1 : entity work.baudgen
    generic map (
      BDDIVIDER => bdDiv(HZ)
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
      EMPTY  => RX_EMPTY,
      FULL   => RX_FULL
    );

  FTX : entity work.fifo
    port map (
      CLK    => CLK,
      RST    => RST,
      RD     => tx_rd,
      WR     => tx_wr,
      W_DATA => DIN,
      R_DATA => tx_dout,
      EMPTY  => TX_EMPTY,
      FULL   => TX_FULL
    );

  URX : entity work.uart_rx
    generic map (
      OVERSAMPLING => ovSamp(HZ)
    )
    port map (
      CLK     => CLK,
      RST     => RST,
      B_TICK  => baudtick,
      RX      => RX,
      RX_DONE => rx_wr,
      RX_BRK  => open,
      DOUT    => rx_din
    );

  UTX : entity work.uart_tx
    generic map (
      OVERSAMPLING => ovSamp(HZ)
    )
    port map (
      CLK      => CLK,
      RESETN   => rst_n,
      B_TICK   => baudtick,
      TX       => TX,
      TX_START => tx_start,
      TX_DONE  => tx_rd,
      D_IN     => tx_dout
    );

  WRITE : process is
  begin

    wait until rising_edge(CLK);

    if (RST = '1') then
      ien   <= (others => '0');
      tx_wr <= '0';
    else
      tx_wr <= '0';
      if (WE = '1') then
        tx_wr <= '1';
      end if;
    end if;

  end process WRITE;

  READ : process (RE, rx_dout) is
  begin

    DOUT  <= (others => '0');
    rx_rd <= '0';

    if (RE = '1') then
      DOUT  <= rx_dout;
      rx_rd <= '1';
    end if;

  end process READ;

end architecture BEHAVIORAL;

