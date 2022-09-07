---------------------------------------------------------------
-- Company:
-- Engineer:
--
-- Create Date:    09:32:01'05.09.2022
-- Design Name:
-- Module Name:    UART_TAP - Behavioral
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
  use IEEE.NUMERIC_STD.ALL;

entity UART_TAP is
  generic (
    CLK_RATE       : integer := 100000000;
    BAUD_RATE      : integer := 3 * 10 ** 6;
    DMI_ABITS      : integer := 7
  );
  port (
    CLK            : in    std_logic;
    RST            : in    std_logic;
    -- UART-Interface connections
    RX             : in    std_logic;
    TX             : out   std_logic;

    -- we want to access DMI register
    DMI_ACCESS_O   : out   std_logic;
    -- JTAG is interested in writing the DTM CSR register
    DTMCS_SELECT_O : out   std_logic;
    -- clear error state
    DMI_RESET_O    : out   std_logic;
    DMI_ERROR_I    : in    std_logic_vector(1 downto 0);
    -- test data to submodule
    DMI_TDI_O      : out   std_logic;
    -- test data in from submodule
    DMI_TDO_I      : in    std_logic
  );
end entity UART_TAP;

architecture BEHAVIORAL of UART_TAP is

  -- UART signals
  signal re,        re_next                                                            : std_logic;
  signal we,        we_next                                                            : std_logic;
  signal tx_ready                                                                      : std_logic;
  signal rx_empty,  rx_full                                                            : std_logic;
  signal din                                                                           : std_logic_vector(7 downto 0);

  type state_t is (st_idle, st_decode, st_instr, st_write, st_send);

  signal state,     state_next                                                         : state_t;

  -- Counts the number of bits received to that register:
  signal blkcount,  blkcount_next                                                      : integer range 0 to DMI_ABITS + 32 + 1;
  signal address,   address_next                                                       : std_logic_vector(7 downto 0);
  signal data_read, data_read_next                                                     : std_logic_vector(6 downto 0);

  signal data_send, data_send_next                                                     : std_logic_vector(7 downto 0);

  constant BYPASS                                                                      : std_logic_vector(7 downto 0) := (others => '0');
  constant IDCODE                                                                      : std_logic_vector(31 downto 0) := X"00000001";
  signal   dtmcs,   dtmcs_next                                                         : std_logic_vector(31 downto 0);
  -- Length is abits + 32 data bits + 2 op bits;
  signal dmi,       dmi_next                                                           : std_logic_vector(DMI_ABITS + 32 + 1 downto 0);

  procedure send_register (
    -- Register to send.
    constant value : in  std_logic_vector;
    -- Current number of send block.
    signal blkcount_reg : in integer;
    -- Next value for outgoing register.
    signal data_next : out std_logic_vector(7 downto 0);
    -- Next value for current send block.
    signal blkcount_next_reg : out  integer;
    -- Only relevant to decide if next state should be;
    -- st_idle, or, if read buffer is not empty, st_read.
    signal rx_empty_reg   : in std_logic;
    signal re_next_reg    : out std_logic;
    signal state_next_reg : out  state_t

  )
      is
  begin

    if (blkcount < (value'length / 8)) then
      data_next         <= value(8 * (blkcount_reg + 1) - 1 downto 8 * blkcount_reg);
      blkcount_next_reg <= blkcount_reg + 1;
    else
      if (blkcount = (value'length / 8) and value'length mod 8 > 0) then
        -- Handle remainder:
        -- Fill leading bits with zero.
        data_next(7 downto value'length mod 8) <= (others => '0');
        -- Put remainder of the register in the lower bits.
        data_next((value'length mod 8) - 1 downto 0) <= value(value'length - 1 downto 8 * blkcount_reg);
        blkcount_next_reg                            <= blkcount_reg + 1;
      else
        blkcount_next_reg <= 0;
        if (rx_empty_reg = '1') then
          state_next_reg <= st_idle;
        else
          state_next_reg <= st_decode;
          re_next_reg    <= '1';
        end if;
      end if;
    end if;

  end procedure send_register;

begin

  UART_1 : entity work.uart
    generic map (
      CLK_RATE  => CLK_RATE,
      BAUD_RATE => BAUD_RATE
    )
    port map (
      CLK      => CLK,
      RST      => RST,
      RX       => RX,
      TX       => TX,
      RE       => re,
      WE       => we,
      TX_READY => tx_ready,
      RX_EMPTY => rx_empty,
      RX_FULL  => rx_full,
      DIN      => din,
      DOUT     => data_send
    );

  FSM_CORE : process (CLK) is
  begin

    if rising_edge(CLK) then
      if (RST = '1') then
        state     <= st_idle;
        blkcount  <= 0;
        re        <= '0';
        we        <= '0';
        data_send <= (others => '0');
        address   <= X"01";
        data_read <= (others => '0');
        dtmcs     <= (others => '0');
        dmi       <= (others => '0');
      else
        state     <= state_next;
        blkcount  <= blkcount_next;
        re        <= re_next;
        we        <= we_next;
        data_send <= data_send_next;
        address   <= address_next;
        data_read <= data_read_next;
        dtmcs     <= dtmcs_next;
        dmi       <= dmi_next;
      end if;
    end if;

  end process FSM_CORE;

  FSM : process (state, rx_empty, din, data_read, data_send, address, blkcount, dtmcs, dmi) is
  begin

    case state is

      when st_idle =>
        re_next        <= '0';
        we_next        <= '0';
        address_next   <= address;
        data_send_next <= (others => '0');
        data_read_next <= (others => '0');
        dtmcs_next     <= dtmcs;
        dmi_next       <= dmi;

        if (rx_empty = '0') then
          re_next    <= '1';
          state_next <= st_decode;
        end if;

      when st_decode =>
        re_next        <= '0';
        we_next        <= '0';
        data_read_next <= din(data_read'length - 1 downto 0);

        if (din(din'length - 1) = '1') then
          -- UART-Packet is instruction as instrucion bit is set
          state_next <= st_instr;
        else
          -- UART-Packet is data
          state_next <= st_write;
        end if;

      when st_instr =>
        -- Assume that the address has changed.
        -- Running writing operations are canceled.
        blkcount_next <= 0;
        address_next  <= "0" & data_read;
        state_next    <= st_send;

      when st_send =>
        we_next <= '1';

        case address is

          when X"01" =>
            send_register (
              value             => IDCODE,
              blkcount_reg      => blkcount,
              data_next       => data_send_next,
              blkcount_next_reg => blkcount_next,
              rx_empty_reg      => rx_empty,
              re_next_reg       => re_next,
              state_next_reg    => state_next);

          when X"10" =>
            send_register (
              value             => dtmcs,
              blkcount_reg      => blkcount,
              data_next       => data_send_next,
              blkcount_next_reg => blkcount_next,
              rx_empty_reg      => rx_empty,
              re_next_reg       => re_next,
              state_next_reg    => state_next);

          when X"11" =>
            send_register (
              value             => dmi,
              blkcount_reg      => blkcount,
              data_next       => data_send_next,
              blkcount_next_reg => blkcount_next,
              rx_empty_reg      => rx_empty,
              re_next_reg       => re_next,
              state_next_reg    => state_next);

          when others =>
            data_send_next <= (others => '0');

            if (rx_empty = '1') then
              state_next <= st_idle;
            else
              state_next <= st_decode;
              re_next    <= '1';
            end if;

        end case;

      when st_write =>

        if (rx_empty = '1') then
          re_next       <= '0';
          blkcount_next <= blkcount;
        else
          re_next       <= '1';
          blkcount_next <= blkcount + 1;
        end if;

        case address is

          when X"10" =>

            if (blkcount < (dtmcs'length) / 7) then
              dtmcs_next(7*(blkcount + 1) - 1 downto 7 * blkcount) <= data_read;
            else
              if (blkcount = (dtmcs'length) / 7 and dtmcs'length mod 7 > 0) then
                dtmcs_next(dtmcs'length - 1 downto 7*blkcount) <= data_read((dtmcs'length mod 7 - 1) downto 0);
              else
                if (rx_empty = '1') then
                  state_next <= st_idle;
                else
                  state_next <= st_decode;
                  re_next    <= '1';
                end if;
              end if;
            end if;

          when X"11" =>

            if (blkcount < (dmi'length) / 7) then
              dmi_next(7*(blkcount + 1) - 1 downto 7 * blkcount) <= data_read;
            else
              if (blkcount = (dmi'length) / 7 and dmi'length mod 7 > 0) then
                dmi_next(dmi'length - 1 downto 7*blkcount) <= data_read((dmi'length mod 7) - 1 downto 0);
              else
                if (rx_empty = '1') then
                  state_next <= st_idle;
                else
                  state_next <= st_decode;
                  re_next    <= '1';
                end if;
              end if;
            end if;

          when others =>

            if (rx_empty = '1') then
              state_next <= st_idle;
            else
              state_next <= st_decode;
              re_next    <= '1';
            end if;

        end case;

    end case;

  end process FSM;

end architecture BEHAVIORAL;
