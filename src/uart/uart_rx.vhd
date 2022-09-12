----------------------------------------------------------------------------------
-- Company:
-- Engineer:
--
-- Create Date:    12:15:23 07/27/2017
-- Design Name:
-- Module Name:    uart_rx - Behavioral
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

entity UART_RX is
  generic (
    OVERSAMPLING : integer := 16
  );
  port (
    CLK     : in    std_logic;
    RST     : in    std_logic;
    B_TICK  : in    std_logic;
    RX_DONE : out   std_logic;
    RX_BRK  : out   std_logic;
    RX      : in    std_logic;
    DOUT    : out   std_logic_vector(7 downto 0)
  );
end entity UART_RX;

architecture BEHAVIORAL of UART_RX is

  type stype is (st_idle, st_start, st_data, st_stop);

  signal state, state_n                               : stype;

  constant CORRECTION_DELAY                           : integer := OVERSAMPLING / 8;
  signal   i                                          : integer range 0 to OVERSAMPLING - 1;
  signal   i_n                                        : integer range 0 to OVERSAMPLING - 1;

  -- signal rx_reg, rx_reg_n                           : std_logic_vector( 2 downto  0);
  signal nbits                                        : integer range 0 to 7;
  signal nbits_n                                      : integer range 0 to 7;
  signal data                                         : std_logic_vector( 7 downto 0);
  signal data_n                                       : std_logic_vector( 7 downto 0);

  signal valid                                        : std_logic;
  signal brk                                          : std_logic;

  signal rx_r                                         : std_logic;

begin

  -- fsm core
  FSM_CORE : process is
  begin

    wait until rising_edge(CLK);

    if (RST = '1') then
      state  <= st_idle;
      i      <= 0;
      nbits  <= 0;
      data   <= (others => '0');
      -- rx_reg <= (others => '0');
    else
      state  <= state_n;
      i      <= i_n;
      nbits  <= nbits_n;
      data   <= data_n;
      -- rx_reg <= rx_reg_n;
    end if;

  end process FSM_CORE;

  -- rx delay
  RX_DELAY : process is
  begin

    wait until rising_edge(CLK);
    rx_r <= RX;

  end process RX_DELAY;

  -- fsm logic
  FSM_LOGIC : process (state, B_TICK, i, nbits, data, RX, rx_r) is
  begin

    -- defaults
    state_n <= state;
    i_n     <= i;
    -- rx_reg_n <= rx_reg;
    nbits_n <= nbits;
    data_n  <= data;
    valid   <= '0';
    brk     <= '0';

    case state is

      when st_idle =>
        valid <= '0';
        -- wait for falling edge
        if (RX = '0' and rx_r = '1') then
          state_n <= st_start;
          i_n     <= 0;
        end if;

      when st_start =>
        valid <= '0';

        if (B_TICK = '1') then
          if (i = OVERSAMPLING / 2 - 1) then
            state_n <= st_data;
            i_n     <= 0;
            nbits_n <= 0;
          else
            i_n <= i + 1;
          end if;
        end if;

      when st_data =>
        valid <= '0';

        if (B_TICK = '1') then
          if (i = OVERSAMPLING - 1) then
            i_n           <= 0;
            data_n(nbits) <= RX;
            if (nbits = 7) then
              state_n <= st_stop;
            else
              nbits_n <= nbits + 1;
            end if;
          else
            i_n <= i + 1;
          end if;
        end if;

      when st_stop =>
        valid <= '0';

        if (B_TICK = '1') then
          if (i = OVERSAMPLING - 1) then
            state_n <= st_idle;
            if (RX = '1') then
              valid <= '1';
            else
              brk <= '1';
            end if;
          else
            i_n <= i + 1;
          end if;
        end if;

    end case;

  end process FSM_LOGIC;

  -- output
  DOUT    <= data;
  RX_DONE <= valid;
  RX_BRK  <= brk;

end architecture BEHAVIORAL;

