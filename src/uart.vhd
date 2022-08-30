----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date:    12:15:23 07/27/2017 
-- Design Name: 
-- Module Name:    uart - Behavioral 
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

use work.baudPack.all;

entity uart is
        generic (mhz: integer := 30
    );
    PORT(
         clk : IN  std_logic;
         rst : IN  std_logic;
         re : IN  std_logic;
         we : IN  std_logic;
         rx : IN  std_logic;
         tx : out  std_logic;
         addr : IN  std_logic_vector(3 downto 0);
         din : IN  std_logic_vector(7 downto 0);
         dout : out  std_logic_vector(7 downto 0);
         irq : OUT  std_logic
        );
end uart;

architecture Behavioral of uart is

	signal rst_n: std_logic;

component BAUDGEN 
    generic (bdDivider: integer := 1);
    port (
        clk: in std_logic;
        rst : in std_logic;
        baudtick: out std_logic
        );
end component;


component fifo
    port (
        clk: in std_logic;
        rst : in std_logic;
        rd: in std_logic;
        wr: in std_logic;
        empty: out std_logic;
        full: out std_logic;
        w_data: in std_logic_vector(7 downto 0);
        r_data: out std_logic_vector(7 downto 0)
    );
end component;


component UART_RX
    generic (oversampling: integer := 16);
    port (
        clk: in std_logic;
        rst : in std_logic;
        b_tick : in std_logic;
        rx : in std_logic;
        rx_brk : out  std_logic;
        rx_done : out std_logic;
        dout: out std_logic_vector(7 downto 0)
    );
end component;
    
component UART_TX
    generic (oversampling: integer := 16);
    port (
        clk: in std_logic;
        resetn : in std_logic;
        b_tick : in std_logic;
        tx : out std_logic;
        tx_start : in std_logic;
        tx_done : out std_logic;
        d_in: in std_logic_vector(7 downto 0)
    );
end component;

	signal baudtick: std_logic;
	signal tx_start: std_logic;
	signal rx_empty, rx_full: std_logic;
	signal tx_empty, tx_full: std_logic;
	signal rx_rd, rx_wr: std_logic;
	signal tx_rd, tx_wr: std_logic;
	signal rx_din, rx_dout: std_logic_vector(7 downto 0);
	signal tx_din, tx_dout: std_logic_vector(7 downto 0);

	-- data: addr 0
    -- control addr 1
    signal ien: std_logic_vector(2 downto 0) := (others => '0');

    -- irq. status bit 0 addr 1
    signal irq_i: std_logic;
    

begin

	rst_n <= not rst;

	b: BAUDGEN
	generic map(bdDiv(mhz)) 
	port map(
		clk => clk,
		rst => rst,			
		baudtick => baudtick
	);

	frx: fifo
	port map(
		clk => clk,
		rst => rst,
		rd => rx_rd,
		wr => rx_wr,
		w_data => rx_din,
		r_data => rx_dout,
		empty => rx_empty,
		full => rx_full
	);

	ftx: fifo
	port map(
		clk => clk,
		rst => rst,
		rd => tx_rd,
		wr => tx_wr,
		w_data => din,
		r_data => tx_dout,
		empty => tx_empty,
		full => tx_full
	);

	urx: UART_RX
	generic map (oversampling => ovSamp(mhz))
    port map(
		clk => clk,
		rst => rst,
      b_tick => baudtick,
	  rx => rx,
	  rx_done => rx_wr,
	  rx_brk => open,
	  dout => rx_din
    );
    
	tx_start <= not tx_empty;
	utx: UART_TX
	generic map (oversampling => ovSamp(mhz))
    port map(
		clk => clk,
		resetn => rst_n,
      b_tick => baudtick,
	  tx => tx,
	  tx_start => tx_start,
	  tx_done => tx_rd,
	  d_in => tx_dout
    );


    -- register write
    process
    begin
        wait until rising_edge(clk);
        if rst = '1' then
            ien <= (others => '0');
				tx_wr <= '0';
        else
				tx_wr <= '0';
				if we = '1' then
					case addr is 
						 when X"0" =>
								tx_wr <= '1';
						 when X"1" =>
							  ien <= din(ien'length - 1 downto 0);
						 when others =>
							  null;
					end case;
				end if;
        end if;
    end process;

    -- register read
    process(addr, re, rx_dout, tx_full, tx_empty, rx_full, rx_empty, irq_i)
    begin
        dout <= (others => '0');
		  rx_rd <= '0';
        if re = '1' then
            case addr is 
                when X"0" =>
                    dout <= rx_dout;
						  rx_rd <= '1';
                when X"1" =>
                    dout <= "000" & tx_full & tx_empty & rx_full & rx_empty & irq_i;
                when others =>
                    null;
            end case;
        end if;
    end process;
    
    -- int control
    process
    begin
        wait until rising_edge(clk);
        if rst = '1' then
                irq_i <= '0';
        else
            irq_i <= '0';
				if ien(0) = '1' and rx_empty = '0' then -- rx data available
					  irq_i <= '1';
				 end if;
				if ien(1) = '1' and rx_full = '1' then -- rx overrun
					  irq_i <= '1';
				 end if;
				if ien(2) = '1' and tx_empty = '1' then -- tx transmit complete
					  irq_i <= '1';
				 end if;
        end if;
    end process;
    irq <= irq_i;



end Behavioral;

