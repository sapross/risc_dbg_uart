---------------------------------------------------------------
-- Company:
-- Engineer:
--
-- Create Date:    09:32:01'05.09.2022
-- Design Name:
-- Module Name:    UART_DTM - Behavioral
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

entity UART_DTM is
  generic (
    CLK_RATE       : integer := 100000000;
    BAUD_RATE      : integer := 3 * 10 ** 6;
    DMI_ABITS      : integer := 5
  );
  port (
    CLK           : in    std_logic;
    RST           : in    std_logic;
    RE            : out   std_logic;
    WE            : out   std_logic;
    TX_READY      : in    std_logic;
    RX_EMPTY      : in    std_logic;
    RX_FULL       : in    std_logic;
    DREC          : in    std_logic_vector(7 downto 0);
    DSEND         : out   std_logic_vector(7 downto 0)
  );
end entity UART_DTM;

architecture BEHAVIORAL of UART_DTM is

  type state_t is (st_idle, st_read, st_decode, st_instr, st_write, st_send);

  signal state,    state_next                                          : state_t;

  -- Counts the number of bits received to that register:
  signal blkcount, blkcount_next                                       : integer range 0 to DMI_ABITS + 32 + 1;
  signal re_i,     re_next                                             : std_logic;
  signal we_i,     we_next                                             : std_logic;
  signal address,  address_next                                        : std_logic_vector(7 downto 0);
  signal dread_i,  dread_next                                          : std_logic_vector(6 downto 0);

  signal to_send                                                       : std_logic;
  signal dsend_i,  dsend_next                                          : std_logic_vector(7 downto 0);

  constant BYPASS                                                      : std_logic_vector(7 downto 0) := (others => '0');
  constant IDCODE                                                      : std_logic_vector(31 downto 0) := X"00000001";
  signal   dtmcs,  dtmcs_next                                          : std_logic_vector(31 downto 0);
  -- Length is abits + 32 data bits + 2 op bits;
  signal dmi,      dmi_next                                            : std_logic_vector(DMI_ABITS + 32 + 1 downto 0);

  procedure send_register (
    -- Register to send.
    constant reg : in  std_logic_vector;
    -- Current number of send block.
    signal blkcount_i : in integer;
    -- Next value for outgoing register.
    signal data_next : out std_logic_vector(7 downto 0);
    -- Next value for current send block.
    signal blkcount_next_i : out  integer;
    -- Only relevant to decide if next state should be;
    -- st_idle, or, if read buffer is not empty, st_read.
    signal rx_empty_i   : in std_logic;
    signal re_next_i    : out std_logic;
    signal state_next_i : out  state_t

  )
      is
  begin
    if (blkcount < (reg'length/8)) then
      data_next <= reg(8 * (blkcount_i + 1) - 1 downto 8 * blkcount_i);
      blkcount_next_i <= blkcount_i + 1;
    else
      if (blkcount = (reg'length/8) and reg'length mod 8 > 0) then
        -- Handle remainder:
        -- Fill leading bits with zero.
        data_next(7 downto reg'length mod 8) <= (others => '0');
        -- Put remainder of the register in the lower bits.
        data_next((reg'length mod 8) -1 downto 0) <= reg(  reg'length downto 8 * blkcount_i);
        blkcount_next_i <= blkcount_i + 1;
      else
        blkcount_next_i <= 0;
        if (rx_empty_i = '1') then
          state_next_i <= st_idle;
        else
          state_next_i <= st_read;
          re_next_i    <= '1';
        end if;
      end if;
    end if;

  end procedure send_register;

begin

  FSM_CORE : process (CLK) is
  begin

    if rising_edge(CLK) then
      if (RST = '1') then
        state    <= st_idle;
        blkcount <= 0;
        re_i     <= '0';
        we_i     <= '0';
        dsend_i  <= (others => '0');
        address  <= (others => '0');
        dread_i  <= (others => '0');
        dtmcs    <= (others => '0');
        dmi      <= (others => '0');
      else
        state    <= state_next;
        blkcount <= blkcount_next;
        re_i     <= re_next;
        we_i     <= we_next;
        dsend_i  <= dsend_next;
        address  <= address_next;
        dread_i  <= dread_next;
        dtmcs    <= dtmcs_next;
        dmi      <= dmi_next;
      end if;
    end if;

  end process FSM_CORE;

  FSM : process (state, blkcount, re_i, we_i, dsend_i, address, dread_i, dtmcs, dmi) is
  begin

    case state is

      when st_idle =>
        re_next <= '0';
        we_next <= '0';

        if (RX_EMPTY = '0') then
          re_next    <= '1';
          state_next <= st_read;
        end if;

      when st_read =>
        re_next    <= '0';
        we_next    <= '0';
        state_next <= st_decode;

      when st_decode =>
        dread_next <= DREC(dread_i'length downto 0);

        if (DREC(DREC'length) = '1') then
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
        address_next  <= dread_i;
        state_next    <= st_send;

      when st_send =>
        we_next <= '1';

        case address is

          when X"01" =>
            send_register (
              reg             => IDCODE,
              blkcount_i      => blkcount,
              data_next       => dsend_next,
              blkcount_next_i => blkcount_next,
              rx_empty_i      => RX_EMPTY,
              re_next_i       => re_next,
              state_next_i    => state_next);

          when X"10" =>
            send_register (
              reg             => dtmcs,
              blkcount_i      => blkcount,
              data_next       => dsend_next,
              blkcount_next_i => blkcount_next,
              rx_empty_i      => RX_EMPTY,
              re_next_i       => re_next,
              state_next_i    => state_next);

          when X"11" =>
            send_register (
              reg             => dmi,
              blkcount_i      => blkcount,
              data_next       => dsend_next,
              blkcount_next_i => blkcount_next,
              rx_empty_i      => RX_EMPTY,
              re_next_i       => re_next,
              state_next_i    => state_next);

          when others =>
            dsend_next <= (others => '0');

            if (RX_EMPTY = '1') then
              state_next <= st_idle;
            else
              state_next <= st_read;
              re_next    <= '1';
            end if;

        end case;

      when st_write =>

        if (RX_EMPTY = '0') then
          re_next       <= '0';
          blkcount_next <= blkcount;
        else
          re_next       <= '1';
          blkcount_next <= blkcount + 1;
        end if;

        case address is

          when X"10" =>
            if (blkcount < (dtmcs'length) / 7) then
              dtmcs_next(7*(blkcount + 1) - 1 downto 7 * blkcount) <= dread_i;
            else
              if (blkcount = (dtmcs'length) / 7 and dtmcs'length mod 7 > 0) then
                dtmcs_next(dtmcs'length downto 7*blkcount) <= dread_i(  dtmcs'length mod 7 downto 0);
              else
                if (RX_EMPTY = '1') then
                  state_next <= st_idle;
                else
                  state_next <= st_read;
                  re_next    <= '1';
                end if;
              end if;
            end if;

          when X"11" =>
            if (blkcount < (dmi'length) / 7) then
              dmi_next(7*(blkcount + 1) - 1 downto 7 * blkcount) <= dread_i;
            else
              if (blkcount = (dmi'length) / 7 and dmi'length mod 7 > 0) then
                dmi_next(dmi'length downto 7*blkcount) <= dread_i(  dmi'length mod 7 downto 0);
              else
                if (RX_EMPTY = '1') then
                  state_next <= st_idle;
                else
                  state_next <= st_read;
                  re_next    <= '1';
                end if;
              end if;
            end if;

          when others =>
            if (RX_EMPTY = '1') then
              state_next <= st_idle;
            else
              state_next <= st_read;
              re_next    <= '1';
            end if;
        end case;

    end case;

  end process FSM;

end architecture BEHAVIORAL;
