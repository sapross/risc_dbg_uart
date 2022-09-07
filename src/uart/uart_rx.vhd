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

  signal state,         state_next             : stype;
  signal sample_reg                            : integer range 0 to OVERSAMPLING - 1;
  signal sample_next                           : integer range 0 to OVERSAMPLING - 1;

  signal num_ones_reg,  num_zeros_reg          : integer range 0 to OVERSAMPLING - 1;
  signal num_ones_next, num_zeros_next         : integer range 0 to OVERSAMPLING - 1;
  signal data_count_reg                        : integer range 0 to 7;
  signal data_count_next                       : integer range 0 to 7;
  signal data_reg                              : std_logic_vector( 7 downto 0);
  signal data_next                             : std_logic_vector( 7 downto 0);

  signal valid                                 : std_logic;
  signal brk                                   : std_logic;

  signal rx_r                                  : std_logic;

begin

  -- fsm core
  process is
  begin

    wait until rising_edge(CLK);

    if (RST = '1') then
      state          <= st_idle;
      sample_reg     <= 0;
      data_count_reg <= 0;
      data_reg       <= (others => '0');
      num_ones_reg   <= 0;
      num_zeros_reg  <= 0;
    else
      state          <= state_next;
      sample_reg     <= sample_next;
      data_count_reg <= data_count_next;
      data_reg       <= data_next;
      num_ones_reg   <= num_ones_next;
      num_zeros_reg  <= num_zeros_next;
    end if;

  end process;

  -- rx delay
  process is
  begin

    wait until rising_edge(CLK);
    rx_r <= RX;

  end process;

  -- fsm logic
  process (state, B_TICK, sample_reg, data_count_reg, data_reg, num_ones_reg, num_zeros_reg, RX, rx_r) is
  begin

    -- defaults
    state_next      <= state;
    sample_next     <= sample_reg;
    num_ones_next   <= num_ones_reg;
    num_zeros_next  <= num_zeros_reg;
    data_count_next <= data_count_reg;
    data_next       <= data_reg;
    valid           <= '0';
    brk             <= '0';

    case state is

      when st_idle =>
        valid <= '0';
        -- wait for falling edge
        if (RX = '0' and rx_r = '1') then
          state_next  <= st_start;
          sample_next <= 0;
        end if;

      when st_start =>
        valid <= '0';

        if (B_TICK = '1') then
          if (sample_reg = OVERSAMPLING - 1) then
            state_next      <= st_data;
            sample_next     <= 0;
            data_count_next <= 0;
          else
            sample_next <= sample_reg + 1;
          end if;
        end if;

      when st_data =>
        valid <= '0';

        if (B_TICK = '1') then
          if (sample_reg = OVERSAMPLING - 1) then
            sample_next <= 0;

            num_ones_next  <= 0;
            num_zeros_next <= 0;

            if (num_ones_reg > num_zeros_reg) then
              data_next <= "1" & data_reg(7 downto 1);
            else
              data_next <= "0" & data_reg(7 downto 1);
            end if;

            if (data_count_reg = 7) then
              state_next <= st_stop;
            else
              data_count_next <= data_count_reg + 1;
            end if;
          else
            sample_next <= sample_reg + 1;
            if (RX = '1') then
              num_ones_next <= num_ones_reg + 1;
            else
              num_zeros_next <= num_zeros_reg + 1;
            end if;
          end if;
        end if;

      when st_stop =>
        valid <= '0';

        if (B_TICK = '1') then
          if (sample_reg = OVERSAMPLING - 1) then
            state_next <= st_idle;
            if (RX = '1') then
              valid <= '1';
            else
              brk <= '1';
            end if;
          else
            sample_next <= sample_reg + 1;
          end if;
        end if;

    end case;

  end process;

  -- output
  DOUT    <= data_reg;
  RX_DONE <= valid;
  RX_BRK  <= brk;

end architecture BEHAVIORAL;

