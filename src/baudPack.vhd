----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

package baudPack is
	function bdDiv(mhz: integer) return integer;
	function ovSamp(mhz: integer) return integer;

end package;

package body baudPack is
    
	function bdDiv(mhz: integer) return integer is
	begin
		if mhz = 50 then 
			report "Uart divider for 50 MHZ: 27";
			return 27;
		elsif mhz = 40 then 
			report "Uart divider for 40 MHZ: 22";
			return 22;
		elsif mhz = 30 then 
			report "Uart divider for 30 MHZ: 16";
			return 16;
		elsif mhz = 25 then 
			report "Uart divider for 25 MHZ: 12";
			report "Required oversampling 18";
			return 12;
		elsif mhz = 20 then 
			report "Uart divider for 20 MHZ: 11";
			return 14;
		elsif mhz = 16 then 
			report "Uart divider for 16 MHZ: 4";
			report "Required oversampling 34";
			return 4;
		elsif mhz = 12 then 
            report "Uart divider for 12 MHZ: 4";
            report "Required oversampling 26";
            return 4;
		elsif mhz = 8 then 
			report "Uart divider for 8 MHZ: 2";
			report "Required oversampleing 34";
			return 2;
		else 
			assert false report "Invalid frequency for baudrate generate" severity failure;
			return 1;
		end if;
	end function;

	function ovSamp(mhz: integer) return integer is
	begin
		if mhz = 50 then 
			report "Oversampling 50 MHZ: 16";
			return 16;
		elsif mhz = 40 then 
			report "Oversampling 40 MHZ: 16";
			return 16;
		elsif mhz = 30 then 
			report "Oversampling 30 MHZ: 16";
			return 16;
		elsif mhz = 25 then 
			report "Oversampling 25 MHZ: 18";
			return 18;
		elsif mhz = 20 then 
			report "Oversampling 20 MHZ: 16";
			return 16;
		elsif mhz = 16 then 
			report "Oversampling 16 MHZ: 34";
			return 34;
		elsif mhz = 12 then 
            report "Oversampling 12 MHZ: 26";
            return 26;
		elsif mhz = 8 then 
			report "Oversampling 8 MHZ: 34";
			return 34;
		else 
			assert false report "Invalid frequency for baudrate generate" severity failure;
			return 1;
		end if;
	end function;

end package body;
