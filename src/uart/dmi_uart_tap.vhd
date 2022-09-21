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
  use IEEE.STD_LOGIC_1164.all;
  use IEEE.NUMERIC_STD.all;

library WORK;
  use WORK.uart_pkg.all;

entity DMI_UART_TAP is
  generic (
    CLK_RATE  : integer := 100000000;
    BAUD_RATE : integer := 3 * 10 ** 6
  );
  port (
    CLK               : in    std_logic;
    RST               : in    std_logic;
    -- UART-Interface connections
    RE_O              : out   std_logic;
    WE_O              : out   std_logic;
    TX_READY_I        : in    std_logic;
    RX_EMPTY_I        : in    std_logic;
    RX_FULL_I         : in    std_logic;
    DSEND_O           : out   std_logic_vector(7 downto 0);
    DREC_I            : in    std_logic_vector(7 downto 0);

    -- JTAG is interested in writing the DTM CSR register
    DTMCS_SELECT_O    : out   std_logic;
    -- clear error state
    DMI_RESET_O       : out   std_logic;
    DMI_ERROR_I       : in    std_logic_vector(1 downto 0);

    -- Output DMI Bus
    DMI_WRITE_READY_I : in    std_logic;
    DMI_WRITE_VALID_O : out   std_logic;
    DMI_WRITE_O       : out   dmi_req_t;
    -- Input DMI Bus
    DMI_READ_READY_O  : out   std_logic;
    DMI_READ_VALID_I  : in    std_logic;
    DMI_READ_I        : in    dmi_resp_t
  );
end entity DMI_UART_TAP;

architecture BEHAVIORAL of DMI_UART_TAP is

  -- UART signals
  signal re,              re_next                                         : std_logic;
  signal we,              we_next                                         : std_logic;
  signal data_read                                                        : std_logic_vector(7 downto 0);
  signal data_send,       data_send_next                                  : std_logic_vector(7 downto 0);

  signal dmi_write_valid, dmi_write_valid_next                            : std_logic;
  signal dmi_write,       dmi_write_next                                  : dmi_req_t;

  signal dmi_read_ready,  dmi_read_ready_next                             : std_logic;
  signal dmi,             dmi_next                                        : std_logic_vector(DMI_REQ_LENGTH - 1 downto 0);
  -- Counts the number of bytes send by/written to that register:
  signal byte_count,      byte_count_next                                 : integer range 0 to DMI_REQ_LENGTH + 1;
  signal data_length,     data_length_next                                : integer range 0 to 255;
  signal address,         address_next                                    : std_logic_vector(7 downto 0);
  signal cmd,             cmd_next                                        : std_logic_vector(2 downto 0);

  signal   dtmcs,         dtmcs_next                                      : std_logic_vector(31 downto 0);

  -- Time Out timer to catch unfished operations.
  -- Each UART-Frame takes 10 baud periods (1 Start + 8 Data + 1 Stop)
  -- Wait for the time of 5 UART-Frames.
  constant MSG_TIMEOUT                                                    : integer := 5 * (10 * CLK_RATE / BAUD_RATE);
  signal   msg_timer                                                      : integer range 0 to MSG_TIMEOUT;
  signal   run_timer                                                      : std_logic;

  type state_t is (
    st_idle,
    st_header,
    st_cmdaddr,
    st_length,
    st_wait_read_dmi,
    st_read,
    st_wait_write_dmi,
    st_write,
    st_rw,
    st_reset
  );

  signal state,           state_next                                      : state_t;

  procedure read_register (
    -- Register to send.
    constant value : in  std_logic_vector;
    -- Next value for outgoing register.
    signal data_next : out std_logic_vector(7 downto 0);
    -- Number of bytes sent.
    signal byte_count_i : in  integer;
    signal we_next_i    : out std_logic;
    -- State to assume after completion.
    constant state_after :     state_t;
    signal state_next_i  : out state_t
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
      we_next_i    <= '0';
      state_next_i <= state_after;
    end if;

  end procedure read_register;

  procedure read_dmi (
    signal dmi_resp   : in  dmi_resp_t;
    signal ready_next : out std_logic;
    signal valid      : in  std_logic;
    signal dmi_i      : in  std_logic_vector;
    signal dmi_next_i : out std_logic_vector
  )
  is
  begin

    report "TAP reads DMI";

    if (valid = '1') then
      dmi_next_i <= dmi_resp_to_stl(dmi_resp);
      ready_next <= '0';
    else
      dmi_next_i <= dmi_i;
      ready_next <= '1';
    end if;

  end procedure read_dmi;

  procedure write_register (
    -- Register to write into.
    signal target      : in std_logic_vector;
    signal target_next : out std_logic_vector;
    -- Value  of for incoming register.
    signal data : in  std_logic_vector(7 downto 0);
    -- Count bytes written.
    signal byte_count_i : in  integer;
    signal rx_empty     : in std_logic;
    signal re_i         : in std_logic;
    signal re_next_i    : out std_logic;
    -- State to assume after completion.
    constant state_after :     state_t;
    signal state_next_i  : out state_t
  )
  is
  begin

    target_next <= target;
    re_next_i   <= '1';

    if (byte_count_i < (target'length / 8)) then
      target_next(8*(byte_count_i + 1) - 1 downto 8 * byte_count_i) <= data;
      if (RX_EMPTY = '1') then
        re_next_i <= '0';
      end if;
    elsif (byte_count_i = (target'length) / 8 and target'length mod 8 > 0) then
      target_next(target'length - 1 downto 8*byte_count_i) <= data((target'length mod 8 - 1) downto 0);
      if (RX_EMPTY = '1') then
        re_next_i <= '0';
      end if;
    else
      re_next_i    <= '0';
      state_next_i <= state_after;
    end if;

  end procedure write_register;

  procedure write_dmi (
    signal dmi_req_next : out dmi_req_t;
    signal ready        : in  std_logic;
    signal valid_next   : out std_logic;
    signal dmi_i        : in  std_logic_vector
  )
  is
  begin

    dmi_req_next <= stl_to_dmi_req(dmi_i);
    valid_next   <= '1';

    if (ready = '1') then
      valid_next <= '0';
    end if;

  end procedure write_dmi;

begin

  DMI_WRITE_VALID_O <= dmi_write_valid;
  DMI_WRITE_O       <= dmi_write;
  DMI_READ_READY_O  <= dmi_read_ready;
  data_read         <= DREC_I;
  DSEND_O           <= data_send;
  WE_O              <= we;
  RE_O              <= re;

  TIMEOUT : process (CLK) is
  begin

    if rising_edge(CLK) then
      if (RST = '1' or run_timer = '0' or RX_EMPTY_I = '0') then
        msg_timer <= 0;
      else
        if (msg_timer < MSG_TIMEOUT and run_timer = '1') then
          msg_timer <= msg_timer + 1;
        end if;
      end if;
    end if;

  end process TIMEOUT;

  FSM_CORE : process (CLK) is
  begin

    if rising_edge(CLK) then
      if (RST = '1') then
        dmi_write <= (addr => (others =>'0'), data => (others=>'0'), op => (others =>'0'));

        re              <= '0';
        we              <= '0';
        data_send       <= (others                 => '0');
        dmi_write_valid <= '0';
        dmi_read_ready  <= '0';
        dmi             <= (others                 => '0');
        byte_count      <= 0;
        data_length     <= 0;
        address         <= X"01";
        cmd             <= CMD_NOP;
        dtmcs           <= (others                 => '0');
        DTMCS_SELECT_O  <= '0';
        state           <= st_idle;
      else
        re              <= re_next;
        we              <= we_next;
        data_send       <= data_send_next;
        dmi_write_valid <= dmi_write_valid_next;
        dmi_write       <= dmi_write_next;
        dmi_read_ready  <= dmi_read_ready_next;
        dmi             <= dmi_next;
        byte_count      <= byte_count_next;
        data_length     <= data_length_next;
        address         <= address_next;
        if (address_next = X"10") then
          DTMCS_SELECT_O <= '1';
        else
          DTMCS_SELECT_O <= '0';
        end if;
        cmd <= cmd_next;
        -- Not all bits of dtmcs a writable:
        dtmcs <= dtmcs_next and DTMCS_WRITE_MASK;
        state <= state_next;
      end if;
    end if;

  end process FSM_CORE;

  FSM : process (state,
                 cmd,
                 we,
                 re,
                 RX_EMPTY_I,
                 TX_READY_I,
                 data_read,
                 data_send,
                 DMI_READ_VALID_I,
                 dmi_read_ready,
                 dmi_write_valid,
                 DMI_WRITE_READY_I,
                 byte_count,
                 data_length,
                 address,
                 dtmcs,
                 dmi,
                 msg_timer) is
  begin

    case state is

      when st_idle =>
        re_next              <= '0';
        we_next              <= '0';
        data_send_next       <= (others => '0');
        dmi_write_valid_next <= '0';
        dmi_write_next       <= (addr => (others => '0'), data => (others => '0'), op => (others => '0'));
        dmi_read_ready_next  <= '0';
        dmi_next             <= dmi;
        byte_count_next      <= 0;
        data_length_next     <= 0;
        address_next         <= address;
        dtmcs_next           <= dtmcs;

        DMI_RESET_O <= '0';
        run_timer   <= '0';

        if (RX_EMPTY_I = '0') then
          re_next    <= '1';
          state_next <= st_header;
        end if;

      when st_header =>
        we_next    <= '0';
        state_next <= st_header;

        if (RX_EMPTY_I = '0') then
          re_next <= '1';
        else
          re_next <= '0';
        end if;

        if (re = '1' and data_read = HEADER) then
          state_next <= st_cmdaddr;
        end if;

      when st_cmdaddr =>
        run_timer  <= '1';
        state_next <= st_cmdaddr;

        if (RX_EMPTY_I = '0') then
          re_next <= '1';
        else
          re_next <= '0';
        end if;

        if (re = '1') then
          cmd_next                            <= data_read(7 downto IrLength);
          address_next(7 downto IrLength)     <= (others => '0');
          address_next(IrLength - 1 downto 0) <= data_read(IrLength - 1 downto 0);
          state_next                          <= st_length;
        elsif (msg_timer = MSG_TIMEOUT) then
          state_next <= st_idle;
        end if;

      -- Assume that the address has changed.
      -- Running writing operations are canceled.
      -- byte_count_next <= 0;
      -- address_next  <= "0" & data_read;
      -- state_next    <= st_send;
      when st_length =>
        state_next <= st_length;
        run_timer  <= '1';

        if (RX_EMPTY_I = '0') then
          re_next <= '1';
        else
          re_next <= '0';
        end if;

        if (re = '1') then
          data_length_next <= to_integer(unsigned(data_read));
          byte_count_next  <= 0;

          case cmd is

            when CMD_READ =>
              if (address = X"11") then
                state_next <= st_wait_read_dmi;
              else
                state_next <= st_read;
              end if;

            when CMD_WRITE =>
              state_next <= st_write;

            when CMD_RW =>
              if (address = X"11") then
                state_next <= st_wait_read_dmi;
              else
                state_next <= st_rw;
              end if;

            when CMD_RESET =>
              state_next <= st_reset;

            when others =>
              state_next <= st_idle;

          end case;

        elsif (msg_timer = MSG_TIMEOUT) then
          state_next <= st_idle;
        end if;

      when st_wait_read_dmi =>
        state_next <= st_wait_read_dmi;

        if (DMI_READ_VALID_I = '0' and dmi_read_ready = '0') then
          dmi_read_ready_next <= '1';
        elsif (DMI_READ_VALID_I = '1' and dmi_read_ready = '1') then
          dmi_next            <= dmi_resp_to_stl(DMI_READ_I);
          dmi_read_ready_next <= '0';

          case cmd is

            when CMD_READ =>
              state_next <= st_read;

            when CMD_RW =>
              state_next <= st_rw;

            when others =>
              state_next <= st_idle;

          end case;

        end if;

      when st_read =>
        state_next <= st_read;
        we_next    <= TX_READY_I;
        run_timer  <= '1';

        if (TX_READY_I = '1') then
          byte_count_next <= byte_count + 1;
        else
          byte_count_next <= byte_count;
        end if;

        if (msg_timer < MSG_TIMEOUT) then

          case address is

            when X"01" =>
              read_register (
                value        => IDCODE,
                data_next    => data_send_next,
                byte_count_i => byte_count,
                we_next_i    => we_next,
                state_after  => st_idle,
                state_next_i => state_next);

            when X"10" =>
              read_register (
                value        => dtmcs,
                data_next    => data_send_next,
                byte_count_i => byte_count,
                we_next_i    => we_next,
                state_after  => st_idle,
                state_next_i => state_next);

            when X"11" =>
              read_register (
                value        => dmi,
                data_next    => data_send_next,
                byte_count_i => byte_count,
                we_next_i    => we_next,
                state_after  => st_idle,
                state_next_i => state_next);

            when others =>
              data_send_next <= (others => '0');
              state_next     <= st_idle;

          end case;

        else
          state_next <= st_idle;
        end if;

      when st_write =>
        state_next      <= st_write;
        run_timer       <= '1';
        byte_count_next <= byte_count;

        if (re = '1') then
          byte_count_next <= byte_count + 1;
        end if;

        if (msg_timer < MSG_TIMEOUT) then

          case address is

            when X"10" =>               -- Write to dtmcs
              write_register (
                  target       => dtmcs,
                  target_next  => dtmcs_next,
                  data         => data_read,
                  byte_count_i => byte_count,
                  rx_empty     => RX_EMPTY_I,
                  re_i         => re,
                  re_next_i    => re_next,
                  state_after  => st_idle,
                  state_next_i => state_next);

            when X"11" =>
              write_register (
                  target       => dmi,
                  target_next  => dmi_next,
                  data         => data_read,
                  byte_count_i => byte_count,
                  rx_empty     => RX_EMPTY_I,
                  re_i         => re,
                  re_next_i    => re_next,
                  state_after  => st_wait_write_dmi,
                  state_next_i => state_next);

            when others =>
              state_next <= st_idle;

          end case;

        else
          state_next <= st_idle;
        end if;

      when st_wait_write_dmi =>
        state_next <= st_wait_write_dmi;
        write_dmi (
          dmi_req_next => dmi_write_next,
          ready        => DMI_WRITE_READY_I,
          valid_next   => dmi_write_valid_next,
          dmi_i        => dmi);

        if (dmi_write_valid = '1' and DMI_WRITE_READY_I = '1') then
          state_next <= st_idle;
        end if;

      when st_rw =>
        state_next <= st_rw;
        run_timer  <= '1';

        if (TX_READY_I = '1' and RX_EMPTY_I = '0') then
          we_next         <= '1';
          re_next         <= '1';
          byte_count_next <= byte_count + 1;
        else
          we_next         <= '1';
          re_next         <= '1';
          byte_count_next <= byte_count;
        end if;

        if (msg_timer < MSG_TIMEOUT) then

          case address is

            when X"01" =>
              read_register (
                value        => IDCODE,
                data_next    => data_send_next,
                byte_count_i => byte_count,
                we_next_i    => we_next,
                state_after  => st_idle,
                state_next_i => state_next);

            when X"10" =>
              read_register (
                value        => dtmcs,
                data_next    => data_send_next,
                byte_count_i => byte_count,
                we_next_i    => we_next,
                state_after  => st_idle,
                state_next_i => state_next);
              write_register (
                target       => dtmcs,
                target_next  => dtmcs_next,
                data         => data_read,
                byte_count_i => byte_count,
                rx_empty     => RX_EMPTY_I,
                re_i         => re,
                re_next_i    => re_next,
                state_after  => st_idle,
                state_next_i => state_next);

            when X"11" =>
              read_register (
                value        => dmi,
                data_next    => data_send_next,
                byte_count_i => byte_count,
                we_next_i    => we_next,
                state_after  => st_wait_write_dmi,
                state_next_i => state_next);
              write_register (
                target       => dmi,
                target_next  => dmi_next,
                data         => data_read,
                byte_count_i => byte_count,
                rx_empty     => RX_EMPTY_I,
                re_i         => re,
                re_next_i    => re_next,
                state_after  => st_wait_write_dmi,
                state_next_i => state_next);

            when others =>
              data_send_next <= (others => '0');

              if (address = X"11") then
                state_next <= st_wait_write_dmi;
              else
                state_next <= st_idle;
              end if;

          end case;

        else
          state_next <= st_idle;
        end if;

      when st_reset =>
        state_next      <= st_idle;
        byte_count_next <= 0;
        re_next         <= '0';
        we_next         <= '0';
        address_next    <= X"01";
        dtmcs_next      <= (others => '0');
        dmi_next        <= (others => '0');
        -- Trigger Reset of DMI module.
        DMI_RESET_O <= '1';
        run_timer   <= '0';

    end case;

  end process FSM;

end architecture BEHAVIORAL;
