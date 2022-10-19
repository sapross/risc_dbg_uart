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

  type state_t is (st_idle, st_start, st_data, st_stop);

  signal state, state_next                               : state_t;

  signal i                                               : integer range 0 to OVERSAMPLING - 1;
  signal i_next                                          : integer range 0 to OVERSAMPLING - 1;

  -- signal rx_reg, rx_reg_n                           : std_logic_vector( 2 downto  0);
  signal nbits                                           : integer range 0 to 7;
  signal nbits_next                                      : integer range 0 to 7;
  signal data                                            : std_logic_vector( 7 downto 0);
  signal data_next                                       : std_logic_vector( 7 downto 0);

  signal baud_period                                     : integer range 0 to OVERSAMPLING + OVERSAMPLING / 2;
  signal p_count                                         : integer range 0 to OVERSAMPLING - 1;

  signal valid                                           : std_logic;
  signal brk                                             : std_logic;

  signal rx_r                                            : std_logic;

  signal baudtick                                        : std_logic;
  signal baud_count, baud_interval                       : integer range 0 to BDDIVIDER + BDDIVIDER / 2;

begin

  CLOCK_RECOVERY : process (CLK) is
  begin

    if (rising_edge(CLK)) then
      -- No need to run generator if state is idle.
      if (RST = '1' or state = st_idle) then
        baudtick <= '0';
        baud_count <= 0;
        baud_interval <= BDDIVIDER -1;
      else
        -- Simple counter/clock divider with variable interval.
        if (baud_count < baud_interval) then
          baud_count <= baud_count +1;
          baudtick <= '0';
        else
          baud_interval <= BDDIVIDER -1;
          baud_count <= 0;
          baudtick <= '1';
        end if;

        --Clock recovery/correction
        --If a edge is found in RX:
        if (rx_r /= RX) then
          -- Are we running early or late?
          if baud_count < BDDIVIDER/2 then
            -- Edge found after expected baudtick.
            -- We are running early, next tick is later.
            baud_interval <= baud_interval + baud_count;
          else
            -- Edge found before expected baudtick.
            -- We are running late, next tick is earlier.
            baud_interval <= baud_interval + BDDIVIDER/2 - baud_count;
          end if;
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
      i     <= 0;
      nbits <= 0;
      data  <= (others => '0');
    -- rx_reg <= (others => '0');
    else
      state <= state_next;
      i     <= i_next;
      nbits <= nbits_next;
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
  FSM_LOGIC : process (state, baudtick, i, nbits, data, RX, rx_r) is
  begin

    -- defaults
    state_next <= state;
    i_next     <= i;
    -- rx_reg_n <= rx_reg;
    nbits_next <= nbits;
    data_next  <= data;
    valid      <= '0';
    brk        <= '0';

    case state is

      when st_idle =>
        valid <= '0';
        -- wait for falling edge
        if (RX = '0' and rx_r = '1') then
          state_next <= st_start;
          i_next     <= 0;
        end if;

      when st_start =>
        valid <= '0';

        if (baudtick = '1') then
          if (i =  OVERSAMPLING / 2  -1) then
            state_next <= st_data;
            i_next     <= 0;
            nbits_next <= 0;
          else
            i_next <= i + 1;
          end if;
        end if;

      when st_data =>
        valid <= '0';

        if (baudtick = '1') then
          if (i = OVERSAMPLING -1) then
            i_next           <= 0;
            data_next(nbits) <= RX;
            if (nbits = 7) then
              state_next <= st_stop;
            else
              nbits_next <= nbits + 1;
            end if;
          else
            i_next <= i + 1;
          end if;
        end if;

      when st_stop =>
        valid <= '0';

        if (baudtick = '1') then
          if (i = OVERSAMPLING -1) then
            state_next <= st_idle;
            if (RX = '1') then
              valid <= '1';
            else
              brk <= '1';
            end if;
          else
            i_next <= i + 1;
          end if;
        end if;

    end case;

  end process FSM_LOGIC;

  -- output
  DOUT    <= data;
  RX_DONE <= valid;
  RX_BRK  <= brk;

end architecture BEHAVIORAL;

