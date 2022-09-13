----------------------------------------------------------------------------------
-- Company:
-- Engineer:
--
-- Create Date:    12:15:23 07/27/2017
-- Design Name:
-- Module Name:    uart_tx - Behavioral
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

entity UART_TX is
  generic (
    OVERSAMPLING : integer := 16
  );
  port (
    CLK      : in    std_logic;
    RESETN   : in    std_logic;
    TX_START : in    std_logic;
    B_TICK   : in    std_logic;
    TX_DONE  : out   std_logic;
    TX       : out   std_logic;
    D_IN     : in    std_logic_vector(7 downto 0)
  );
end entity UART_TX;

architecture BEHAVIORAL of UART_TX is

  signal rst               : std_logic;

  type stype is (st_idle, st_send);

  signal state, state_next : stype;
  signal b_reg             : integer range 0 to OVERSAMPLING - 1;
  signal b_next            : integer range 0 to OVERSAMPLING - 1;
  signal c_reg             : integer range 0 to 9;
  signal c_next            : integer range 0 to 9;
  signal d_reg             : std_logic_vector( 9 downto 0);
  signal d_next            : std_logic_vector( 9 downto 0);
  signal t_reg, t_next     : std_logic;

begin

  rst <= not RESETN;

  -- fsm core
  FSM_CORE : process is
  begin

    wait until rising_edge(CLK);

    if (rst = '1') then
      state <= st_idle;
      t_reg <= '1';
      b_reg <= 0;
      c_reg <= 0;
      d_reg <= (others => '0');
    else
      state <= state_next;
      b_reg <= b_next;
      c_reg <= c_next;
      d_reg <= d_next;
      t_reg <= t_next;
    end if;

  end process FSM_CORE;

  -- fsm logic
  FSM_LOGIC : process (state, B_TICK, b_reg, c_reg, d_reg, t_reg, D_IN, TX_START) is
  begin

    -- defaults
    state_next <= state;
    b_next     <= b_reg;
    c_next     <= c_reg;
    d_next     <= d_reg;
    t_next     <= t_reg;
    TX_DONE    <= '0';

    case state is

      when st_idle =>
        t_next <= '1';

        if (TX_START = '1') then
          b_next     <= 0;
          c_next     <= 0;
          d_next     <= '1' & D_IN & '0';
          state_next <= st_send;
        end if;

      when st_send =>
        t_next <= d_reg(0);

        if (B_TICK = '1') then
          if (b_reg = OVERSAMPLING - 1) then
            b_next <= 0;
            d_next <= '1' & d_reg(9 downto 1);
            if (c_reg = 9) then
              state_next <= st_idle;
              TX_DONE    <= '1';
            else
              c_next <= c_reg + 1;
            end if;
          else
            b_next <= b_reg + 1;
          end if;
        end if;

      when others =>
        null;

    end case;

  end process FSM_LOGIC;

  -- output
  TX <= t_reg;

end architecture BEHAVIORAL;
