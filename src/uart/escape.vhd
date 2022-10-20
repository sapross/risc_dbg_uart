---------------------------------------
-- Author: Stephan Proß
--
-- Create Date: 03/08/2022 02:46:11 PM
-- Design Name:
-- Module Name: ESCAPE - Behavioral
-- Project Name: UART-DTM
-- Tool Versions: Vivado 2021.2
-- Description: Simulation testing functionality of escape filter.
----------------------------------------------------------------------------------

library IEEE;
  use IEEE.STD_LOGIC_1164.all;
  use IEEE.NUMERIC_STD.all;

entity ESCAPE is
  generic (
    ESC_SYMBOL : std_logic_vector(7 downto 0) := x"B1"
  );
  port (
    CLK        : in    std_logic;
    RST        : in    std_logic;
    RX_RE_O    : out   std_logic;
    DREC_I     : in    std_logic_vector( 7 downto 0);
    RX_EMPTY_I : in    std_logic;
    DREC_O     : out   std_logic_vector( 7 downto 0);
    VALID_O    : out   std_logic;
    ESC_O      : out   std_logic;
    RE_I       : in    std_logic
  );
end entity ESCAPE;

architecture BEHAVIORAL of ESCAPE is

  type state_t is (
    st_idle,
    st_data,
    st_escape,
    st_command
  );

  signal state, state_next : state_t;
  signal data, data_next   : std_logic_vector( 7 downto 0);

begin

  FSM_CORE : process(CLK) is
  begin
    if(rising_edge(CLK)) then
      if (RST = '1') then
        state <= st_idle;
        data <= (others => '0');
      else
        state <= state_next;
        data <= data_next;
      end if;
    end if;
  end process;

  FSM : process(state, RX_EMPTY_I, RE_I, DREC_I) is
  begin
    state_next <= state;
    data_next <= data;
    ESC_O <= '0';
    VALID_O <= '0';
    RX_RE_O <= '0';

    if (RST = '1') then
      state_next <= st_idle;
      data_next <= (others => '0');
    else
      case (state) is
        when st_idle =>
          if (RX_EMPTY_I = '0') then
            data_next <= DREC_I;
            if(DREC_I = ESC_SYMBOL) then
              state_next <= st_escape;
            else
              state_next <= st_data;
            end if;
          end if;

        when st_data =>
          VALID_O <= '1';
          if (RE_I = '1') then
            state_next <= st_idle;
          end if;

        when st_escape =>
          if(RX_EMPTY_I = '0') then
            data_next <= DREC_I;
            state_next <= st_command;
          end if;

        when st_command =>
          ESC_O <= '1';
          VALID_O <= '1';
          if (RE_I <= '1') then
            state_next <= st_idle;
          end if;
      end case;
    end if;
  end process;

  OUTPUT : process (state,RE_I, data) is
  begin
    if (RST = '1') then
      DREC_O <= (others => '0');
    else
      DREC_O <= (others => '0');
      if (RE_I = '1') then
        DREC_O <= data;
      end if;
    end if;
  end process;

end architecture BEHAVIORAL;
