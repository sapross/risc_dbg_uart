---------------------
-- Author: Stephan Proß
--
-- Create Date: 03/08/2022 02:46:11 PM
-- Design Name:
-- Module Name: TB_De_Serializer - Behavioral
-- Project Name: UART-DTM
-- Tool Versions: Vivado 2021.2
-- Description: Simulation testing functionality of UART Test Access Point.
----------------------------------------------------------------------------------

library IEEE;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.math_real.uniform;
  use ieee.math_real.floor;

library WORK;
  use work.uart_pkg.all;

entity TB_DE_SERIALIZER is
end entity TB_DE_SERIALIZER;

architecture TB of TB_DE_SERIALIZER is

  constant CLK_RATE      : integer := 100 * 10 ** 6;  -- Hz
  constant CLK_PERIOD    : time    := 10 ns;          -- ns;

  constant MAX_BYTES     : integer := 4;

  signal clk             : std_logic;
  signal rst             : std_logic;

  signal num_bits        : unsigned( 7 downto 0);
  signal reg_i,  reg_o   : std_logic_vector(8 * MAX_BYTES - 1 downto 0);
  signal data_i, data_o  : std_logic_vector(7 downto 0);
  signal run_0           : std_logic;
  signal run_1           : std_logic;
  signal done            : std_logic;

begin

  -- Plug serializer entity into deserializer.
  SERIALIZER_1 : entity work.de_serializer
    generic map (
      MAX_BYTES => MAX_BYTES
    )
    port map (
      CLK        => clk,
      RST        => rst,
      NUM_BITS_I => num_bits,
      D_I        => X"00",
      D_O        => data_o,
      REG_I      => reg_i,
      REG_O      => open,
      RUN_I      => run_0,
      DONE_O     => done
    );

  DESERIALIZER_1 : entity work.de_serializer
    generic map (
      MAX_BYTES => MAX_BYTES
    )
    port map (
      CLK        => clk,
      RST        => rst,
      NUM_BITS_I => num_bits,
      D_I        => data_o,
      D_O        => open,
      REG_I      => (others => '0'),
      REG_O      => reg_o,
      RUN_I      => run_1,
      DONE_O     => open
    );

  CLK_PROCESS : process is
  begin

    clk <= '0';
    wait for CLK_PERIOD / 2;
    clk <= '1';
    wait for CLK_PERIOD / 2;

  end process CLK_PROCESS;

  RUN_DELAY : process is
  begin

    while (true) loop

      -- Delay the second run signal by one cycle.
      -- Only required as we plug one serializer into a deserializer.
      run_1 <= run_0;
      wait for CLK_PERIOD;

    end loop;

  end process RUN_DELAY;

  MAIN : process is
  begin

    rst   <= '1';
    run_0 <= '0';
    wait for CLK_PERIOD;
    rst   <= '0';
    -- Start running the de-/serializers.
    run_0    <= '1';
    reg_i    <= X"000ABCDE";
    num_bits <= to_unsigned(20, num_bits'length);
    -- -- Check whether interrupting the de-/serializers has an effect on the results.
    -- run_0 <= '0';
    -- wait for 2 * clk_period;
    -- run_0 <= '1'
    -- 20 Bits should take ceil(20/8) + 1 cycles.
    wait for ( 3 + 1) * CLK_PERIOD;
    run_0 <= '0';
    assert done = '1';
    assert reg_i = reg_o;
    wait for CLK_PERIOD;
    assert done = '0';
    -- Second run with 24 bits and break.
    run_0    <= '1';
    reg_i    <= X"00FEDCBA";
    num_bits <= to_unsigned(24, num_bits'length);
    -- Check whether interrupting the de-/serializers has an effect on the results.
    run_0 <= '0';
    wait for 2 * CLK_PERIOD;
    run_0 <= '1';
    -- 24 Bits should take ceil(24/8) = 3 and  1 cycle.
    wait for ( 3 + 1) * CLK_PERIOD;
    run_0 <= '0';
    assert done = '1';
    assert reg_i = reg_o;
    wait for CLK_PERIOD;
    assert done = '0';
    wait;

  end process MAIN;

end architecture TB;
