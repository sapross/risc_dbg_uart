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
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

  use work.baudPack.all;

entity UART_7SEG_TOP is
  generic (
    CLK_RATE  : integer := 10 ** 8;
    BAUD_RATE : integer := 115200 -- 3 * 10 ** 6
  );
  port (
    CLK       : in    std_logic;
    RSTN      : in    std_logic;
    RXD_DEBUG : in    std_logic;
    TXD_DEBUG : out   std_logic;
    C         : out   std_logic_vector(6 downto 0);
    DP        : out   std_logic;
    AN        : out   std_logic_vector(7 downto 0);
    LED       : out   std_logic_vector(15 downto 0);
    BTNC      : in    std_logic
  );
end entity UART_7SEG_TOP;

architecture BEHAVIORAL of UART_7SEG_TOP is

  signal rst                        : std_logic;
  signal rx_done                    : std_logic;
  signal rx_brk                     : std_logic;
  signal re,      we                : std_logic;
  signal re_next, we_next           : std_logic;
  signal dsend                      : std_logic_vector(7 downto 0);
  signal dsend_next                 : std_logic_vector(7 downto 0);
  signal drec                       : std_logic_vector(7 downto 0);
  signal tx_ready                   : std_logic;
  signal counter, counter_next      : integer range 0 to 255;
  signal led_sanity                 : std_logic;
  signal sig_rxd, sig_txd           : std_logic;

  signal btn,     btn_prev          : std_logic;
  signal outbuf                     : std_logic_vector(31 downto 0);

begin

  -- Nexys4 has low active buttons.
  rst <= not RSTN;
  --  sig_rxd   <= RXD_DEBUG when SW = '0' else
  --               RXD;
  --  TXD_DEBUG <= sig_txd when SW = '0' else
  --               '1';
  --  TXD       <= sig_txd when SW = '1' else
  --               '1';

  UART_RX_1: entity work.UART_RX
    generic map (
      OVERSAMPLING => ovSamp(CLK_RATE),
      BDDIVIDER    => bdDiv(CLK_RATE, BAUD_RATE)
      )
    port map (
      CLK     => CLK,
      RST     => rst,
      RX_DONE => rx_done,
      RX_BRK  => rx_brk,
      RX      => RXD_DEBUG,
      DOUT    => drec);

  LED(15 downto 2) <= (others => '0');
  LED(1 downto 0)  <= rx_brk & rx_done;

  shift : process(CLK) is
  begin
    if (rising_edge(CLK)) then
      if (RST = '1') then
        outbuf <= (others =>'0');
      else
        if (rx_done = '1') then
          outbuf <= outbuf(23 downto 0 ) & drec;
        end if;
      end if;
    end if;
  end process;


  -- DEBOUNCER_1 : entity work.debouncer
  --   generic map (
  --     TIMEOUT_CYCLES => 100
  --   )
  --   port map (
  --     CLK    => CLK,
  --     RST    => rst,
  --     INPUT  => BTNC,
  --     OUTPUT => btn
  --   );

  -- ENABLE_SEND : process (CLK) is
  -- begin

  --   if rising_edge(CLK) then
  --     if (rst = '1') then
  --       we     <= '0';
  --       re     <= '0';
  --       dsend  <= (others => '0');
  --       outbuf <= (others => '0');
  --     else
  --       btn_prev <= btn;
  --       if (btn_prev = '0' and btn = '1') then
  --         if (rx_done = '0') then
  --           re <= '1';
  --         end if;
  --       else
  --         re <= '0';
  --       end if;

  --       if (re = '1' and tx_ready = '1') then
  --         we     <= '1';
  --         dsend  <= drec;
  --         outbuf <= drec;
  --       else
  --         we    <= '0';
  --         dsend <= (others => '0');
  --       end if;
  --     end if;
  --   end if;

  -- end process ENABLE_SEND;

  SEGSEVEN : process (CLK) is

    variable digit   : std_logic_vector(3 downto 0);
    variable sel     : integer range 0 to 7;
    variable counter : integer range 0 to 100000;

  begin

    if (rising_edge(CLK)) then
      if (rst = '1') then
        counter := 0;
        digit   := (others => '0');
        sel     := 0;
        AN      <= (others => '0');
        C       <= (others => '1');
        DP      <= '1';
      else
        if (counter /= 100000) then
          counter := counter + 1;
        else
          counter := 0;
          digit := outbuf((sel+1)*4 -1 downto sel*4);
          AN    <= "11111111";
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
