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

entity baudgen is
    generic (
		--! Frequency divider
		bdDivider: integer := 27
	 );
    PORT(
		--! Clock
         clk : IN  std_logic;
		--! Reset
         rst : IN  std_logic;
		--! Enable pulse, active for 1 cycle every bdDivider cycles
         baudtick : OUT  std_logic
        );
end baudgen;

architecture Behavioral of baudgen is

begin

	--! Counter with synchronous reset. Restart at bdTick limit
    bdCounter: process
        variable cnt: integer;
    begin
        wait until rising_edge(clk);
        baudtick <= '0';
        if rst = '1' then
            cnt := 0;
        elsif cnt < bdDivider - 1 then
            cnt := cnt + 1;
        else
            cnt := 0;
            baudtick <= '1';
        end if;
    end process;


end Behavioral;
