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

  constant CLK_RATE                   : integer := 100 * 10 ** 6;  -- Hz
  constant CLK_PERIOD                 : time    := 10 ns;          -- ns;

  constant MAX_BYTES                  : integer := 4;

  signal clk                          : std_logic;
  signal rst,       rst_n             : std_logic;

  signal num_bits                     : unsigned( 7 downto 0);
  signal reg_i,     reg_o             : std_logic_vector(8 * MAX_BYTES - 1 downto 0);
  signal data_i,    data_o            : std_logic_vector(7 downto 0);
  signal run                          : std_logic;
  signal done                         : std_logic;
  signal dummy_reg                    : std_logic_vector(8 * MAX_BYTES - 1 downto 0);
  signal dummy_data                   : std_logic_vector(7 downto 0);
  signal dummy_done                   : std_logic;
  signal valid_ser, valid_deser       : std_logic;

begin

  rst_n <= not rst;

  -- Plug serializer entity into deserializer.
  SERIALIZER_1 : entity work.de_serializer
    generic map (
      MAX_BYTES => MAX_BYTES
    )
    port map (
      CLK_I      => clk,
      RST_NI     => rst_n,
      NUM_BITS_I => num_bits,
      BYTE_I     => X"00",
      BYTE_O     => data_o,
      REG_I      => reg_i,
      REG_O      => dummy_reg,
      RUN_I      => run,
      VALID_O    => valid_ser,
      DONE_O     => done
    );

  DESERIALIZER_1 : entity work.de_serializer
    generic map (
      MAX_BYTES => MAX_BYTES
    )
    port map (
      CLK_I      => clk,
      RST_NI     => rst_n,
      NUM_BITS_I => num_bits,
      BYTE_I     => data_o,
      BYTE_O     => dummy_data,
      REG_I      => (others => '0'),
      REG_O      => reg_o,
      RUN_I      => valid_ser,
      VALID_O    => valid_deser,
      DONE_O     => dummy_done
    );

  CLK_PROCESS : process is
  begin

    clk <= '0';
    wait for CLK_PERIOD / 2;
    clk <= '1';
    wait for CLK_PERIOD / 2;

  end process CLK_PROCESS;

  MAIN : process is
  begin

    rst <= '1';
    run <= '0';
    wait for CLK_PERIOD;
    rst <= '0';
    -- Start running the de-/serializers.
    run      <= '1';
    reg_i    <= X"000ABCDE";
    num_bits <= to_unsigned(20, num_bits'length);
    -- -- Check whether interrupting the de-/serializers has an effect on the results.
    -- run <= '0';
    -- wait for 2 * clk_period;
    -- run <= '1'
    -- 20 Bits should take ceil(20/8) + 1 cycles.
    wait for ( 3 + 1) * CLK_PERIOD;
    run <= '0';
    assert done = '1';
    assert reg_i = reg_o;
    rst <= '1';
    wait for CLK_PERIOD;
    rst <= '0';
    assert done = '0';
    -- Second run with 24 bits and break.
    run      <= '1';
    reg_i    <= X"00FEDCBA";
    num_bits <= to_unsigned(24, num_bits'length);
    -- Check whether interrupting the de-/serializers has an effect on the results.
    run <= '0';
    wait for 2 * CLK_PERIOD;
    run <= '1';
    -- 24 Bits should take ceil(24/8) = 3 and  1 cycle.
    wait for ( 3 + 1) * CLK_PERIOD;
    run <= '0';
    assert done = '1';
    assert reg_i = reg_o;
    wait for CLK_PERIOD;
    assert done = '0';
    wait;

  end process MAIN;

end architecture TB;
