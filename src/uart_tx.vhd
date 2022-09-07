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


entity uart_tx is
    generic (oversampling: integer := 16);
    PORT(
         clk : IN  std_logic;
         resetn : IN  std_logic;
         tx_start : IN  std_logic;
         b_tick : IN  std_logic;
         tx_done : out  std_logic;
         tx : out  std_logic;
         d_in : IN  std_logic_vector(7 downto 0)
        );
end uart_tx;

architecture Behavioral of uart_tx is
	 signal rst: std_logic;
	 
	 type stype is (st_idle, st_send);
	 signal state,state_next: stype;
	 signal b_reg: integer range 0 to oversampling - 1;
	 signal b_next: integer range 0 to oversampling - 1;
	 signal c_reg: integer range 0 to 9;
	 signal c_next: integer range 0 to 9;
	 signal d_reg: std_logic_vector( 9 downto 0);
	 signal d_next: std_logic_vector( 9 downto 0);
	 signal t_reg, t_next: std_logic;
	 
begin
	
	rst <= not resetn;

	-- fsm core
	process
	begin
		wait until rising_edge(clk);
		if rst = '1' then
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
	end process;
	
	-- fsm logic
	process(state, b_tick, b_reg, c_reg, d_reg, t_reg, d_in, tx_start)
	begin
		-- defaults
		state_next <= state;
		b_next <= b_reg;
		c_next <= c_reg;
		d_next <= d_reg;
		t_next <= t_reg;
		tx_done <= '0';
		
		case state is
			when st_idle =>
				t_next <= '1';
				if tx_start = '1' then
					b_next <= 0;
					c_next <= 0;
					d_next <= '1' & d_in & '0';
					state_next <= st_send;
				end if;
				
			when st_send =>
				t_next <= d_reg(0);
				if b_tick = '1' then
					if b_reg = oversampling - 1 then
						b_next <= 0;
						d_next <= '1' & d_reg(9 downto 1);
						if c_reg = 9 then
							state_next <= st_idle;
							tx_done <= '1';
						else
							c_next <= c_reg + 1;
						end if;
					else
						b_next <= b_reg + 1;
					end if;
				end if;

			when others => null;
		end case;
	end process;
	
	-- output
	tx <= t_reg;
	
end Behavioral;
