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
    OVERSAMPLING : integer := 16;
    BDDIVIDER    : integer := 27
  );
  port (
    CLK     : in    std_logic;
    RST     : in    std_logic;
    RX_DONE : out   std_logic;
    RX_BRK  : out   std_logic;
    RX      : in    std_logic;
    DOUT    : out   std_logic_vector(7 downto 0)
  );
end entity UART_RX;

architecture BEHAVIORAL of UART_RX is

  type state_t is (st_idle, st_start, st_bit0, st_bit1, st_bit2, st_bit3, st_bit4, st_bit5, st_bit6, st_bit7, st_stop);

  signal state,        state_next                               : state_t;

  signal data                                                   : std_logic_vector( 7 downto 0);
  signal data_next                                              : std_logic_vector( 7 downto 0);

  signal valid                                                  : std_logic;
  signal brk                                                    : std_logic;

  signal rx_r                                                   : std_logic;

  constant MAX_BAUD_COUNT                                       : integer := 3 * OVERSAMPLING * BDDIVIDER / 2;
  constant SMPL_INTERVAL                                : integer := OVERSAMPLING * BDDIVIDER;
  signal   baudtick                                             : std_logic;
  signal   baud_count, baud_interval                            : integer range 0 to MAX_BAUD_COUNT - 1;

begin

  CLOCK_RECOVERY : process (CLK) is
  begin

    if (rising_edge(CLK)) then
      -- No need to run generator if state is idle.
      if (RST = '1' or state = st_idle) then
        baudtick      <= '0';
        baud_count    <= 0;
        baud_interval <= SMPL_INTERVAL / 2 - 1;
      else
        -- Simple counter/clock divider with variable interval.
        if (baud_count < baud_interval) then
          baud_count <= baud_count + 1;
          baudtick   <= '0';
        else
          baud_interval <= SMPL_INTERVAL - 1;
          baud_count    <= 0;
          baudtick      <= '1';
        end if;

        -- Clock recovery/correction
        -- If a edge is found in RX:
        if (rx_r /= RX) then
          baud_interval <= baud_interval - (OVERSAMPLING * BDDIVIDER / 2 - baud_count);
        end if;
      end if;
    end if;

  end process CLOCK_RECOVERY;

  -- fsm core
  FSM_CORE : process is
  begin

    wait until rising_edge(CLK);

    if (RST = '1') then
      state <= st_idle;
      data  <= (others => '0');
    -- rx_reg <= (others => '0');
    else
      state <= state_next;
      data  <= data_next;
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
  FSM_LOGIC : process (state, baudtick, data, RX, rx_r) is
  begin

    -- defaults
    state_next <= state;
    -- rx_reg_n <= rx_reg;
    data_next <= data;
    valid     <= '0';
    brk       <= '0';

    case state is

      when st_idle =>
        valid <= '0';
        -- wait for falling edge
        if (RX = '0' and rx_r = '1') then
          state_next <= st_start;
        end if;

      when st_start =>
        valid <= '0';

        if (baudtick = '1') then
          state_next <= st_bit0;
        end if;

      when st_bit0 =>
        valid <= '0';

        if (baudtick = '1') then
          state_next   <= st_bit1;
          data_next(0) <= rx_r;
        end if;

      when st_bit1 =>
        valid <= '0';

        if (baudtick = '1') then
          state_next   <= st_bit2;
          data_next(1) <= rx_r;
        end if;

      when st_bit2 =>
        valid <= '0';

        if (baudtick = '1') then
          state_next   <= st_bit3;
          data_next(2) <= rx_r;
        end if;

      when st_bit3 =>
        valid <= '0';

        if (baudtick = '1') then
          state_next   <= st_bit4;
          data_next(3) <= rx_r;
        end if;

      when st_bit4 =>
        valid <= '0';

        if (baudtick = '1') then
          state_next   <= st_bit5;
          data_next(4) <= rx_r;
        end if;

      when st_bit5 =>
        valid <= '0';

        if (baudtick = '1') then
          state_next   <= st_bit6;
          data_next(5) <= rx_r;
        end if;

      when st_bit6 =>
        valid <= '0';

        if (baudtick = '1') then
          state_next   <= st_bit7;
          data_next(6) <= rx_r;
        end if;

      when st_bit7 =>
        valid <= '0';

        if (baudtick = '1') then
          state_next   <= st_stop;
          data_next(7) <= rx_r;
        end if;

      when st_stop =>

        if (baudtick = '1') then
          -- if (i = OVERSAMPLING - 1) then
          state_next <= st_idle;
          valid      <= '1';
          -- if (rx_r = '1') then
          -- else
          --   brk <= '1';
          -- end if;
          -- else
          --   i_next <= i + 1;
          -- end if;
        end if;

    end case;

  end process FSM_LOGIC;

  -- output
  DOUT    <= data;
  RX_DONE <= valid;
  RX_BRK  <= brk;

end architecture BEHAVIORAL;

