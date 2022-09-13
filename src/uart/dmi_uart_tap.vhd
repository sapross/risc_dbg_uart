---------------------------------------------------------------
-- Company:
-- Engineer:
--
-- Create Date:    09:32:01'05.09.2022
-- Design Name:
-- Module Name:    dmi_uart_tap - Behavioral
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
--

library IEEE;
  use IEEE.STD_LOGIC_1164.ALL;
  use IEEE.NUMERIC_STD.ALL;

library work;
  use work.uart_pkg.ALL;

entity DMI_UART_TAP is
  generic (
    CLK_RATE       : integer := 100000000;
    BAUD_RATE      : integer := 3 * 10 ** 6
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
end entity DMI_UART_TAP;

architecture BEHAVIORAL of DMI_UART_TAP is

  -- UART signals
  signal re,         re_next                                                              : std_logic;
  signal we,         we_next                                                              : std_logic;
  signal tx_ready                                                                         : std_logic;
  signal rx_empty,   rx_full                                                              : std_logic;
  signal din                                                                              : std_logic_vector(7 downto 0);

  -- Counts the number of bytes send by/written to that register:
  signal byte_count, byte_count_next                                                      : integer range 0 to DMI_ABITS + 32 + 1;
  signal address,    address_next                                                         : std_logic_vector(7 downto 0);
  signal data_read                                                                        : std_logic_vector(7 downto 0);

  signal data_send,  data_send_next                                                       : std_logic_vector(7 downto 0);

  constant BYPASS                                                                         : std_logic_vector(7 downto 0) := (others => '0');
  constant IDCODE                                                                         : std_logic_vector(31 downto 0) := X"00000001";
  signal   dtmcs,    dtmcs_next                                                           : std_logic_vector(31 downto 0);
  -- Length is abits + 32 data bits + 2 op bits;
  signal dmi,        dmi_next                                                             : std_logic_vector(DMI_ABITS + 32 + 1 downto 0);

  type state_t is (
    st_idle, st_header, st_cmdaddr, st_length, st_read, st_write, st_rw, st_reset
  );

  signal state,      state_next                                                           : state_t;

  procedure read_register (
    -- Register to send.
    constant value : in  std_logic_vector;
    -- Next value for outgoing register.
    signal data_next : out std_logic_vector(7 downto 0);
    -- Number of bytes sent.
    signal byte_count_i : in integer;
    signal we_next_i    : out std_logic;
    signal state_next_i : out  state_t
  )
      is
  begin

    if (byte_count_i < (value'length / 8)) then
      data_next <= value(8 * (byte_count_i + 1) - 1 downto 8 * byte_count_i);
    elsif (byte_count_i = (value'length / 8) and value'length mod 8 > 0) then
      -- Handle remainder:
      -- Fill leading bits with zero.
      data_next(7 downto value'length mod 8) <= (others => '0');
      -- Put remainder of the register in the lower bits.
      data_next((value'length mod 8) - 1 downto 0) <= value(value'length - 1 downto 8 * byte_count_i);
    else
      we_next      <= '0';
      state_next_i <= st_idle;
    end if;

  end procedure read_register;

  procedure write_register (
    -- Register to write into.
    signal target : out  std_logic_vector;
    -- Value  of for incoming register.
    signal data : in std_logic_vector(7 downto 0);
    -- Count bytes written.
    signal byte_count_i : in integer;
    signal re_next_i    : out std_logic;
    signal state_next_i : out  state_t
  )
      is
  begin

    if (byte_count_i < (target_i'length) / 8) then
      target(8*(byte_count_i + 1) - 1 downto 8 * byte_count_i) <= data;
    elsif (byte_count_i = (target'length) / 8 and target'length mod 8 > 0) then
      target(target'length - 1 downto 8*byte_count_i) <= data((target'length mod 8 - 1) downto 0);
    else
      re_next_i    <= '0';
      state_next_i <= st_idle;
    end if;

  end procedure write_register;

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
      DIN      => data_send,
      DOUT     => data_read
    );

  FSM_CORE : process (CLK) is
  begin

    if rising_edge(CLK) then
      if (RST = '1') then
        state        <= st_idle;
        byte_count_i <= 0;
        re           <= '0';
        we           <= '0';
        data_send    <= (others => '0');
        address      <= X"01";
        data_read    <= (others => '0');
        dtmcs        <= (others => '0');
        dmi          <= (others => '0');
      else
        state        <= state_next;
        byte_count_i <= byte_count_next;
        re           <= re_next;
        we           <= we_next;
        data_send    <= data_send_next;
        address      <= address_next;
        dtmcs        <= dtmcs_next;
        dmi          <= dmi_next;
      end if;
    end if;

  end process FSM_CORE;

  FSM : process (state, rx_empty, data_read, data_read, data_send, address, byte_count_i, dtmcs, dmi) is
  begin

    case state is

      when st_idle =>
        re_next        <= '0';
        we_next        <= '0';
        address_next   <= address;
        data_send_next <= (others => '0');
        dtmcs_next     <= dtmcs;
        dmi_next       <= dmi;

        if (rx_empty = '0') then
          re_next    <= '1';
          state_next <= st_header;
        end if;

      when st_header =>
        we_next    <= '0';
        state_next <= st_header;

        if (rx_empty = '0') then
          re_next <= '1';
        else
          re_next <= '0';
        end if;

        if (re = '1' and data_read = HEADER) then
          state_next <= st_cmdaddr;
        end if;

      when st_cmdaddr =>
        state_next <= st_cmdaddr;

        if (rx_empty = '0') then
          re_next <= '1';
        else
          re_next <= '0';
        end if;

        if (re = '1') then
          cmd_next     <= data_read(7 downto IrLength);
          address_next <= data_read(IrLength - 1 downto 0);
          state_next   <= st_length;
        end if;

      -- Assume that the address has changed.
      -- Running writing operations are canceled.
      -- byte_count_next <= 0;
      -- address_next  <= "0" & data_read;
      -- state_next    <= st_send;
      when st_length =>
        state_next <= st_length;

        if (rx_empty = '0') then
          re_next <= '1';
        else
          re_next <= '0';
        end if;

        if (re = '1') then
          data_length_next <= data_read;
          data_count_next  <= 0;

          case cmd is

            when CMD_READ =>
              state_next <= st_read;

            when CMD_WRITE =>
              state_next <= st_write;

            when CMD_RW =>
              state_next <= st_rw;

            when CMD_RESET =>
              state_next <= st_reset;

            when others =>
              state_next <= st_idle;

          end case;

        end if;

      when st_read =>
        state_next <= st_read;
        we_next    <= tx_ready;

        if (tx_ready = '1') then
          byte_count_next <= byte_count + 1;
        else
          byte_count_next <= byte_count;
        end if;

        case address is

          when X"01" =>
            read_register (
              value             => IDCODE,
              data_next         => data_send_next,
              byte_count_i      => byte_count_i,
              we_next_i         => we_next,
              state_next_reg    => state_next);

          when X"10" =>
            read_register (
              value             => dtmcs,
              data_next         => data_send_next,
              byte_count_i      => byte_count_i,
              we_next_i         => we_next,
              state_next_reg    => state_next);

          when X"11" =>
            -- TODO: Delegate DMI read to dmi_uart module.
            read_register (
              value             => dmi,
              data_next         => data_send_next,
              byte_count_i      => byte_count,
              we_next_i         => we_next,
              state_next_reg    => state_next);

          when others =>
            data_send_next <= (others => '0');
            state_next     <= st_idle;

        end case;

      when st_write =>
        state_next <= st_write;

        if (rx_empty = '1') then
          re_next         <= '0';
          byte_count_next <= byte_count;
        else
          re_next         <= '1';
          byte_count_next <= byte_count + 1;
        end if;

        case address is

          when X"10" => -- Write to dtmcs
            write_register (
              target       => dtmcs_next,
              data         => data_read,
              byte_count_i => byte_count,
              re_next_i    => re_next,
              state_next_i => state_next);

          when X"11" =>
            -- TODO: Delegate DMI write to dmi_uart module.
            write_register (
              target       => dmi_next,
              data         => data_read,
              byte_count_i => byte_count,
              re_next_i    => re_next,
              state_next_i => state_next);

          when others =>
            state_next <= st_idle;

        end case;

      when st_rw =>
        state_next <= st_rw;

        if (tx_ready = '1' and rx_empty = '0') then
          we_next         <= '1';
          re_next         <= '1';
          byte_count_next <= byte_count + 1;
        else
          we_next         <= '1';
          re_next         <= '1';
          byte_count_next <= byte_count;
        end if;

        case address is

          when X"01" =>
            read_register (
              value             => IDCODE,
              data_next         => data_send_next,
              byte_count_i      => byte_count_i,
              we_next_i         => we_next,
              state_next_reg    => state_next);

          when X"10" =>
            read_register (
              value             => dtmcs,
              data_next         => data_send_next,
              byte_count_i      => byte_count_i,
              we_next_i         => we_next,
              state_next_reg    => state_next);
            write_register (
              target       => dtmcs_next,
              data         => data_read,
              byte_count_i => byte_count,
              re_next_i    => re_next,
              state_next_i => state_next);

          when X"11" =>
            -- TODO: Delegate DMI RW to dmi_uart module.
            read_register (
              value             => dmi,
              data_next         => data_send_next,
              byte_count_i      => byte_count,
              we_next_i         => we_next,
              state_next_reg    => state_next);
            write_register (
              target       => dmi_next,
              data         => data_read,
              byte_count_i => byte_count,
              re_next_i    => re_next,
              state_next_i => state_next);

          when others =>
            data_send_next <= (others => '0');
            state_next     <= st_idle;

        end case;

      when st_reset =>
        -- TODO: Create and relay reset signal to dmi_uart
        state        <= st_idle;
        byte_count_i <= 0;
        re           <= '0';
        we           <= '0';
        data_send    <= (others => '0');
        address      <= X"01";
        data_read    <= (others => '0');
        dtmcs        <= (others => '0');
        dmi          <= (others => '0');
    end case;

  end process FSM;

end architecture BEHAVIORAL;
