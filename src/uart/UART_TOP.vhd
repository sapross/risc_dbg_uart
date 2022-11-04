---------------------------------------------------------------
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

entity UART_TOP is
  generic (
    CLK_RATE  : integer := 25 * 10**6; --10 ** 8;
    BAUD_RATE : integer := 3 * 10 ** 6 -- 115200 
  );
  port (
    CLK       : in    std_logic;
    pll_locked: out std_logic;
    RSTN      : in    std_logic;
    RXD_DEBUG : in    std_logic;
    TXD_DEBUG : out   std_logic
    
    --    RXD       : in    std_logic;
    --    TXD       : out   std_logic
    --    LED       : out   std_logic;
    --    SW        : in    std_logic
  );
end entity UART_TOP;

architecture BEHAVIORAL of UART_TOP is

  signal sys_clk : std_logic;
  signal rst                                 : std_logic;
  signal dsend                               : std_logic_vector(7 downto 0);
  signal drec,    dout                       : std_logic_vector(7 downto 0);
  signal rx_done, tx_done                    : std_logic;
  signal tx_start                            : std_logic;
  signal sig_rxd, sig_txd                    : std_logic;
  signal baudtick                            : std_logic;

begin

  -- Nexys4 has low active buttons.
  rst <= not RSTN;
  
  CLK_WIZ_I : entity work.clk_wiz_0
    port map (
      CLK_IN1  => CLK,
      CLK_OUT1 => sys_clk,
      locked => pll_locked
    );

  
  --  sig_rxd   <= RXD_DEBUG when SW = '0' else
  --               RXD;
  --  TXD_DEBUG <= sig_txd when SW = '0' else
  --               '1';
  --  TXD       <= sig_txd when SW = '1' else
  --               '1';
  sig_rxd   <= RXD_DEBUG;
  TXD_DEBUG <= sig_txd;

  UART_RX_1 : entity work.uart_rx
    generic map (
      OVERSAMPLING => ovSamp(CLK_RATE),
      BDDIVIDER    => bdDiv(CLK_RATE, BAUD_RATE)
    )
    port map (
      CLK     => sys_clk,
      RST     => rst,
      RX_DONE => rx_done,
      RX_BRK  => open,
      RX      => sig_rxd,
      DOUT    => drec
    );

  BAUDGEN_1 : entity work.baudgen
    generic map (
      BDDIVIDER => bdDiv(CLK_RATE, BAUD_RATE)
    )
    port map (
      CLK      => sys_clk,
      RST      => rst,
      BAUDTICK => baudtick
    );

  UTX : entity work.uart_tx
    generic map (
      OVERSAMPLING => ovSamp(CLK_RATE)
    )
    port map (
      CLK      => sys_clk,
      RESETN   => RSTN,
      B_TICK   => baudtick,
      TX       => sig_txd,
      TX_START => tx_start,
      TX_DONE  => tx_done,
      D_IN     => dout
    );

  TRANSMIT : process (sys_clk) is
  begin

    if rising_edge(sys_clk) then
      if (rst = '1') then
        dout     <= (others => '0');
        tx_start <= '0';
      else
        if (rx_done = '1') then
          dout     <= drec;
          tx_start <= '1';
        end if;
        if (tx_done = '1') then
          tx_start <= '0';
        end if;
      end if;
    end if;

  end process TRANSMIT;

end architecture BEHAVIORAL;
