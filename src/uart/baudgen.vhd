----------------------------------------------------------------------------------
----------------------------------------------------------------------------------

library IEEE;
  use IEEE.STD_LOGIC_1164.ALL;
  use IEEE.NUMERIC_STD.ALL;

--! @brief Baud rate generator entity
--! @details
--! Generate enable pulse, active for 1 cycle every bdDivider cycles \n
--! Divider has to be set depending on clock frequency and desired baud Generate \n
--! Example: Assuming on oversampling rate of 8, 25MHz clock, 115200 Baud => divider = 27 \n

--! @param[in] Generic: bdDivider Frequency Divider
--! @param[in] clk clock
--! @param[in] rst reset
--! @param[out] baudtick Enable pulse, active for 1 cycle every bdDivider cycles

entity BAUDGEN is
  generic (
    --! Frequency divider
    BDDIVIDER : integer := 27
  );
  port (
    --! Clock
    CLK      : in    std_logic;
    --! Reset
    RST      : in    std_logic;
    --! Enable pulse, active for 1 cycle every bdDivider cycles
    BAUDTICK : out   std_logic
  );
end entity BAUDGEN;

architecture BEHAVIORAL of BAUDGEN is

begin

  --! Counter with synchronous reset. Restart at bdTick limit
  BDCOUNTER : process is

    variable cnt : integer;

  begin

    wait until rising_edge(CLK);
    BAUDTICK <= '0';

    if (RST = '1') then
      cnt := 0;
    elsif (cnt < BDDIVIDER - 1) then
      cnt := cnt + 1;
    else
      cnt      := 0;
      BAUDTICK <= '1';
    end if;

  end process BDCOUNTER;

end architecture BEHAVIORAL;
