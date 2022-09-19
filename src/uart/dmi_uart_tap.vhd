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
use work.uart_pkg.all;

entity DMI_UART_TAP is
  generic (
    CLK_RATE  : integer := 100000000;
    BAUD_RATE : integer := 3 * 10 ** 6
    );
  port (
    CLK      : in  std_logic;
    RST      : in  std_logic;
    -- UART-Interface connections
    RE_O       : out std_logic;
    WE_O       : out std_logic;
    TX_READY_I : in  std_logic;
    RX_EMPTY_I : in  std_logic;
    RX_FULL_I  : in  std_logic;
    DIN_O      : out std_logic_vector(7 downto 0);
    DOUT_I     : in  std_logic_vector(7 downto 0);

    -- JTAG is interested in writing the DTM CSR register
    DTMCS_SELECT_O : out std_logic;
    -- clear error state
    DMI_RESET_O    : out std_logic;
    DMI_ERROR_I    : in  std_logic_vector(1 downto 0);

    -- Output DMI Bus
    DMI_WRITE_READY_I : in  std_logic;
    DMI_WRITE_VALID_O : out std_logic;
    DMI_WRITE_O       : out dmi_req_t;
    -- Input DMI Bus
    DMI_READ_READY_O  : out std_logic;
    DMI_READ_VALID_I  : in  std_logic;
    DMI_READ_I        : in  dmi_resp_t
    );
end entity DMI_UART_TAP;

architecture BEHAVIORAL of DMI_UART_TAP is

  -- UART signals
  signal re_next               : std_logic;
  signal we_next               : std_logic;
  signal data_read                 : std_logic_vector(7 downto 0);
  signal data_send, data_send_next : std_logic_vector(7 downto 0);

  signal dmi_write_valid, dmi_write_valid_next : std_logic;
  signal dmi_write, dmi_write_next             : dmi_req_t;

  signal dmi_read_ready, dmi_read_ready_next : std_logic;
  signal dmi, dmi_next                       : std_logic_vector(DMI_REQ_LENGTH - 1 downto 0);
  -- Counts the number of bytes send by/written to that register:
  signal byte_count, byte_count_next         : integer range 0 to RMI_REQ_LENGTH + 1;
  signal data_length, data_length_next       : integer range 0 to 255;
  signal address, address_next               : std_logic_vector(7 downto 0);
  signal cmd, cmd_next                       : std_logic_vector(2 downto 0);

  constant BYPASS          : std_logic_vector(7 downto 0)  := (others => '0');
  constant IDCODE          : std_logic_vector(31 downto 0) := X"00000001";
  signal dtmcs, dtmcs_next : std_logic_vector(31 downto 0);

  -- Time Out timer to catch unfished operations.
  -- Each UART-Frame takes 10 baud periods (1 Start + 8 Data + 1 Stop)
  -- Wait for the time of 5 UART-Frames.
  constant MSG_TIMEOUT : integer := 5*(10 * CLK_RATE/BAUD_RATE);
  signal msg_timer     : integer range 0 to MSG_TIMEOUT;
  signal run_timer     : std_logic;

  type state_t is (
    st_idle,
    st_header,
    st_cmdaddr,
    st_length,
    st_wait_read_dmi,
    st_read,
DMI_UART_TAP_1    st_wait_write_dmi,
    st_write,
    st_rw,
    st_reset
    );

  signal state, state_next : state_t;

  procedure read_register (
    -- Register to send.
    constant value       : in  std_logic_vector;
    -- Next value for outgoing register.
    signal data_next     : out std_logic_vector(7 downto 0);
    -- Number of bytes sent.
    signal byte_count_i  : in  integer;
    signal we_next_i     : out std_logic;
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
      data_next(7 downto value'length mod 8)       <= (others => '0');
      -- Put remainder of the register in the lower bits.
      data_next((value'length mod 8) - 1 downto 0) <= value(value'length - 1 downto 8 * byte_count_i);
    else
      we_next      <= '0';
      state_next_i <= st_idle;
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

    dmi_next_i <= dmi_i;
    ready_next <= '1';

    if (valid = '1') then
      dmi_next_i <= dmi_resp_to_stl(dmi_resp);
      ready_next <= '0';
    end if;

  end procedure read_dmi;

  procedure write_register (
    -- Register to write into.
    signal target        : out std_logic_vector;
    -- Value  of for incoming register.
    signal data          : in  std_logic_vector(7 downto 0);
    -- Count bytes written.
    signal byte_count_i  : in  integer;
    signal re_next_i     : out std_logic;
    -- State to assume after completion.
    constant state_after :     state_t;
    signal state_next_i  : out state_t
    )
  is
  begin

    if (byte_count_i < (target'length) / 8) then
      target(8*(byte_count_i + 1) - 1 downto 8 * byte_count_i) <= data;
    elsif (byte_count_i = (target'length) / 8 and target'length mod 8 > 0) then
      target(target'length - 1 downto 8*byte_count_i) <= data((target'length mod 8 - 1) downto 0);
    else
      re_next_i    <= '0';
      state_next_i <= st_idle;
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

    dmi_req_next <= stl_to_dmi_req(dmi_req);
    valid_next   <= '1';

    if (ready = '1') then
      valid_next <= '0';
    end if;

  end procedure write_dmi;

begin

  DMI_WRITE_VALID_O <= dmi_write_valid;
  DMI_WRITE_O       <= dmi_write;
  DMI_READ_READY_O  <= dmi_read_ready;
  data_read <= DOUT_I;
  DIN_O <= data_send;


  MSG_TIMEOUT : process(CLK) is
  begin
    if rising_edge(CLK) then
      if (RST = '1' or run_timer = '0' or rx_empty_I = '0') then
        msg_timer <= 0;
      else
        if msg_timer < MSG_TIMEOUT and run_timer = '1' then
          msg_timer <= msg_timer + 1;
        end if;
      end if;
    end if;
  end process;

  FSM_CORE : process (CLK) is
  begin

    if rising_edge(CLK) then
      if (RST = '1') then
        re_O              <= '0';
        we_O              <= '0';
        data_send       <= (others                 => '0');
        data_read       <= (others                 => '0');
        dmi_write_valid <= '0';
        dmi_write       <= dmi_resp_to_stl((others => '0'));
        dmi_read_ready  <= '0';
        dmi             <= (others                 => '0');
        byte_count      <= 0;
        data_length     <= 0;
        address         <= X"01";
        cmd             <= CMD_NOP;
        dtmcs           <= (others                 => '0');
        state           <= st_idle;
      else
        re_O              <= re_next;
        we_O              <= we_next;
        data_send       <= data_send_next;
        data_read       <= data_read_next;
        dmi_write_valid <= dmi_write_valid_next;
        dmi_write       <= dmi_write_next;
        dmi_read_ready  <= dmi_read_ready_next;
        dmi             <= dmi_next;
        byte_count      <= byte_count_next;
        data_length     <= data_length_next;
        address         <= address_next;
        cmd             <= cmd_next;
        -- Not all bits fo dtmcs a writable:
        dtmcs           <= dtmcs_next and DTMCS_WRITE_MASK;
        state           <= state_next;
      end if;
    end if;

  end process FSM_CORE;

  FSM : process (state, rx_empty_I, data_read, data_read, data_send, address, byte_count, dtmcs, dmi) is
  begin

    case state is

      when st_idle =>
        re_next        <= '0';
        we_next        <= '0';
        address_next   <= address;
        data_send_next <= (others => '0');
        dtmcs_next     <= dtmcs;
        dmi_next       <= dmi;
        DMI_RESET_O    <= '0';

        run_timer <= '0';
        if (rx_empty_I = '0') then
          re_next    <= '1';
          state_next <= st_header;
        end if;

      when st_header =>
        we_next    <= '0';
        state_next <= st_header;

        if (rx_empty_I = '0') then
          re_next <= '1';
        else
          re_next <= '0';
        end if;

        if (re_O = '1' and data_read = HEADER) then
          state_next <= st_cmdaddr;
        end if;

      when st_cmdaddr =>
        run_timer  <= '1';
        state_next <= st_cmdaddr;

        if (rx_empty_I = '0') then
          re_next <= '1';
        else
          re_next <= '0';
        end if;

        if (re_O = '1') then
          cmd_next     <= data_read(7 downto IrLength);
          address_next <= data_read(IrLength - 1 downto 0);
          state_next   <= st_length;
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

        if (rx_empty_I = '0') then
          re_next <= '1';
        else
          re_next <= '0';
        end if;

        if (re_O = '1') then
          data_length_next <= data_read;
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
        read_dmi (
          dmi_resp   => DMI_READ_I,
          ready_next => dmi_read_ready_next,
          valid      => DMI_READ_VALID_I,
          dmi_i      => dmi,
          dmi_next_i => dmi_next);

        if (DMI_READ_VALID_I = '1' and dmi_read_ready = '1') then

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
        we_next    <= tx_ready_I;
        run_timer  <= '1';
        if (tx_ready_I = '1') then
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
        state_next <= st_write;
        run_timer  <= '1';
        if (rx_empty_I = '1') then
          re_next         <= '0';
          byte_count_next <= byte_count;
        else
          re_next         <= '1';
          byte_count_next <= byte_count + 1;
        end if;

        if (msg_timer < MSG_TIMEOUT) then
          case address is

            when X"10" =>               -- Write to dtmcs
              write_register (
                target       => dtmcs_next,
                data         => data_read,
                byte_count_i => byte_count,
                re_next_i    => re_next,
                state_after  => st_idle,
                state_next_i => state_next);

            when X"11" =>
              write_register (
                target       => dmi_next,
                data         => data_read,
                byte_count_i => byte_count,
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

        if (tx_ready_I = '1' and rx_empty_I = '0') then
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
                target       => dtmcs_next,
                data         => data_read,
                byte_count_i => byte_count,
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
                target       => dmi_next,
                data         => data_read,
                byte_count_i => byte_count,
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
        state       <= st_idle;
        byte_count  <= 0;
        re_O          <= '0';
        we_O          <= '0';
        data_send   <= (others => '0');
        address     <= X"01";
        data_read   <= (others => '0');
        dtmcs       <= (others => '0');
        dmi         <= (others => '0');
        -- Trigger Reset of DMI module.
        DMI_RESET_O <= '1';
        run_timer   <= '0';

    end case;

  end process FSM;

end architecture BEHAVIORAL;
