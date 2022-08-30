----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date:    16:39:26 08/09/2017 
-- Design Name: 
-- Module Name:    fifo - Behavioral 
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

-- Uncomment the following library declaration if instantiating
-- any Xilinx primitives in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity fifo is
	generic (
		abits: integer := 4;
		dbits: integer := 8
	);
	port (
         clk : IN  std_logic;
         rst : IN  std_logic;
         rd : IN  std_logic;
         wr : IN  std_logic;
         w_data : IN  std_logic_vector(7 downto 0);
         r_data : out  std_logic_vector(7 downto 0);
			full: out std_logic;
			empty: out std_logic
	);
end fifo;

architecture Behavioral of fifo is
	
	subtype dtype is std_logic_vector(dbits - 1 downto 0);
	subtype atype is std_logic_vector(abits - 1 downto 0);
	type ramType is array(0 to 2**abits - 1) of dtype;
	signal ram: ramType;
	signal w_ptr, w_ptr_next, w_ptr_succ : integer range 0 to 2**abits - 1;
	signal r_ptr, r_ptr_next, r_ptr_succ : integer range 0 to 2**abits - 1;
	signal full_i, full_next : std_logic;
	signal empty_i, empty_next : std_logic;
	signal w_en : std_logic;
 
begin

	-- protect write
	w_en <= '1' when wr = '1' and full_i = '0' else '0';

	-- write
	process
	begin
		wait until rising_edge(clk);
		if w_en = '1' then
			ram(w_ptr mod 2**abits) <= w_data;
		end if;
	end process;

	-- read
	process(r_ptr,ram)
	begin
		r_data <= ram(r_ptr mod 2**abits);
	end process;

	-- fsm core
	process
	begin
		wait until rising_edge(clk);
		if rst = '1' then
			w_ptr <= 0;
			r_ptr <= 0;
			full_i <= '0';
			empty_i <= '1';
		else
			w_ptr <= w_ptr_next;
			r_ptr <= r_ptr_next;
			full_i <= full_next;
			empty_i <= empty_next;
		end if;
	end process;
	
	-- fsm logic
	process(w_ptr, r_ptr, w_ptr_succ, r_ptr_succ, full_i, empty_i, rd, w_en)
		variable c: std_logic_vector(1 downto 0);
	begin
    w_ptr_succ <= (w_ptr + 1) mod 2**abits;
    r_ptr_succ <= (r_ptr + 1) mod 2**abits;
    
    w_ptr_next <= w_ptr;
    r_ptr_next <= r_ptr;

    full_next <= full_i;
    empty_next <= empty_i;

	 c := w_en & rd;
	 case c is
		-- read only
		when "01" =>  
        if empty_i = '0' then
            r_ptr_next <= r_ptr_succ;
            full_next <= '0';
            if r_ptr_succ = w_ptr then
              empty_next <= '1';
				end if;
         end if;
		
		-- write only
		when "10" => 
        if full_i = '0' then
            w_ptr_next <= w_ptr_succ;
            empty_next <= '0';
            if w_ptr_succ = r_ptr then
              full_next <= '1';
				end if;
          end if;
		
		-- read and write
		when "11" => 
          w_ptr_next <= w_ptr_succ;
          r_ptr_next <= r_ptr_succ;
		
		-- idle
		when others => null;
	end case;
	end process;

	-- flags
	full <= full_i;
	empty <= empty_i;

end Behavioral;

