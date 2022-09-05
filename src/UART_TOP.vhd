---------------------------------------------------------------
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

entity UART_TOP is
  generic (
    CLK_RATE       : integer := 100000000;
    BAUD_RATE      : integer := 3*10**6
  );
  port (
    CLK       : in    std_logic;
    RST       : in    std_logic;
    RXD       : in    std_logic;
    TXD       : out   std_logic
  );
end entity UART_TOP;

architecture BEHAVIORAL of UART_TOP is

  signal rx_empty                         : std_logic;
  signal rx_full                          : std_logic;
  signal re,      we                      : std_logic;
  signal re_next, we_next                 : std_logic;
  signal din                              : std_logic_vector(7 downto 0);
  signal din_next                         : std_logic_vector(7 downto 0);
  signal dout                             : std_logic_vector(7 downto 0);
  signal ready                            : std_logic;
  signal counter, counter_next            : integer range 0 to 255;

begin

  UART_1 : entity work.uart
    generic map (
      CLK_RATE  => CLK_RATE,
      BAUD_RATE => BAUD_RATE
    )
    port map (
      CLK      => CLK,
      RST      => RST,
      RE       => re,
      WE       => we,
      RX       => RXD,
      TX       => TXD,
      READY    => ready,
      RX_EMPTY => rx_empty,
      RX_FULL  => rx_full,
      DIN      => din,
      DOUT     => dout
    );

  re <= '1' when rx_empty ='0' and ready = '1' else
        '0';

  ECHO : process (CLK) is
  begin

    if rising_edge(CLK) then
      if (RST = '1') then
        we      <= '0';
        din     <= (others => '0');
        -- counter <= 0;
      else
        if re = '1' then
          we      <= '1';
          din     <= dout;
          -- din     <= std_logic_vector(to_unsigned(counter, din'length));
          -- counter <= counter + 1;
        else
          we      <= '0';
          din     <= (others => '0');
          -- counter <= counter;
        end if;
      end if;
    end if;

  end process ECHO;

end architecture BEHAVIORAL;
