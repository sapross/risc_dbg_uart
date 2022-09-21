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

  type fsm_t is record
    -- UART-Interface signals
    re        : std_logic;
    we        : std_logic;
    data_send : std_logic_vector(7 downto 0);
    -- DMI-Interace Signals
    dmi_write_valid : std_logic;
    dmi_write       : dmi_req_t;
    dmi_read_ready  : std_logic;
    dmi             : std_logic_vector(DMI_REQ_LENGTH - 1 downto 0);
    dtmcs           : std_logic_vector(31 downto 0);
    -- FSM Signals
    byte_count  : integer range 0 to DMI_REQ_LENGTH + 1;
    data_length : integer range 0 to 255;
    address     : std_logic_vector(IrLength - 1 downto 0);
    cmd         : std_logic_vector(2 downto 0);
    state       : state_t;
  end record;

  signal fsm, fsm_next                                                    : fsm_t;

  -- Time Out timer to catch unfished operations.
  -- Each UART-Frame takes 10 baud periods (1 Start + 8 Data + 1 Stop)
  -- Wait for the time of 5 UART-Frames.
  constant MSG_TIMEOUT                                                    : integer := 5 * (10 * CLK_RATE / BAUD_RATE);
  signal   msg_timer                                                      : integer range 0 to MSG_TIMEOUT;
  signal   run_timer                                                      : std_logic;

  procedure read_register (
    -- Register to send.
    constant value       :     std_logic_vector;
    constant state_after :     state_t;
    signal fsm_i         : in fsm_t;
    signal fsm_next_i    : out fsm_t
  )
  is
  begin

    if (fsm_i.byte_count < (value'length / 8)) then
      fsm_next_i.data_send <= value(8 * (fsm_i.byte_count + 1) - 1 downto 8 * fsm_i.byte_count);
    elsif (fsm_i.byte_count = (value'length / 8) and value'length mod 8 > 0) then
      -- Handle remainder:
      -- Fill leading bits with zero.
      fsm_next_i.data_send(7 downto value'length mod 8) <= (others => '0');
      -- Put remainder of the register in the lower bits.
      fsm_next_i.data_send((value'length mod 8) - 1 downto 0) <= value(value'length - 1 downto 8 * fsm.byte_count);
    else
      fsm_next_i.we    <= '0';
      fsm_next_i.state <= state_after;
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
    signal target        : in std_logic_vector;
    signal target_next   : out std_logic_vector;
    signal rx_empty      : in std_logic;
    signal data_read     : in std_logic_vector(7 downto 0);
    signal fsm_i         : in fsm_t;
    signal fsm_next_i    : out fsm_t;
    constant state_after :     state_t
  )
  is
  begin

    target_next   <= target;
    fsm_next_i.re <= '1';

    if (fsm_i.byte_count < (target'length / 8)) then
      target_next(8*(fsm_i.byte_count + 1) - 1 downto 8 * fsm_i.byte_count) <= data_read;
      if (RX_EMPTY = '1') then
        fsm_next_i.re <= '0';
      end if;
    elsif (fsm_i.byte_count = (target'length) / 8 and target'length mod 8 > 0) then
      target_next(target'length - 1 downto 8*fsm_i.byte_count) <= data_read((target'length mod 8 - 1) downto 0);
      if (RX_EMPTY = '1') then
        fsm_next_i.re <= '0';
      end if;
    else
      fsm_next_i.re    <= '0';
      fsm_next_i.state <= state_after;
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

  DMI_WRITE_VALID_O <= fsm.dmi_write_valid;
  DMI_WRITE_O       <= fsm.dmi_write;
  DMI_READ_READY_O  <= fsm.dmi_read_ready;

  DSEND_O <= fsm.data_send;
  WE_O    <= fsm.we;
  RE_O    <= fsm.re;

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
        fsm.dmi_write <= (addr => (others =>'0'), data => (others=>'0'), op => (others =>'0'));

        fsm.re              <= '0';
        fsm.we              <= '0';
        fsm.data_send       <= (others                 => '0');
        fsm.dmi_write_valid <= '0';
        fsm.dmi_read_ready  <= '0';
        fsm.dmi             <= (others                 => '0');
        fsm.byte_count      <= 0;
        fsm.data_length     <= 0;
        fsm.address         <= ADDR_IDCODE;
        fsm.cmd             <= CMD_NOP;
        DTMCS_SELECT_O      <= '0';
        fsm.dtmcs           <= dtmcs_to_stl(DTMCS_ZERO);
        fsm.state           <= st_idle;
      else
        fsm       <= fsm_next;
        fsm.dtmcs           <= dtmcs_to_stl(DTMCS_ZERO);
        fsm.dtmcs(17 downto 16) <= fsm_next.dtmcs(17 downto 16);
        if (fsm_next.address = ADDR_DTMCS) then
          DTMCS_SELECT_O <= '1';
        else
          DTMCS_SELECT_O <= '0';
        end if;
      end if;
    end if;

  end process FSM_CORE;

  FSM_COMB : process (fsm, DREC_I, RX_EMPTY_I, TX_READY_I, DMI_READ_VALID_I, DMI_WRITE_READY_I, msg_timer) is
  begin

    fsm_next <= fsm;

    case fsm.state is

      when st_idle =>
        fsm_next.re              <= '0';
        fsm_next.we              <= '0';
        fsm_next.data_send       <= (others => '0');
        fsm_next.dmi_write_valid <= '0';
        fsm_next.dmi_write       <= (addr => (others => '0'), data => (others => '0'), op => (others => '0'));
        fsm_next.dmi_read_ready  <= '0';
        fsm_next.byte_count      <= 0;
        fsm_next.data_length     <= 0;

        fsm_next.cmd <= CMD_NOP;

        DMI_RESET_O  <= '0';
        run_timer    <= '0';

        if (RX_EMPTY_I = '0') then
          fsm_next.re    <= '1';
          fsm_next.state <= st_header;
        end if;

      when st_header =>
        fsm_next.we    <= '0';
        fsm_next.state <= st_header;

        if (RX_EMPTY_I = '0') then
          fsm_next.re <= '1';
        else
          fsm_next.re <= '0';
        end if;

        if (fsm.re = '1' and DREC_I = HEADER) then
          fsm_next.state <= st_cmdaddr;
        end if;

      when st_cmdaddr =>
        run_timer      <= '1';
        fsm_next.state <= st_cmdaddr;

        if (RX_EMPTY_I = '0') then
          fsm_next.re <= '1';
        else
          fsm_next.re <= '0';
        end if;

        if (fsm.re = '1') then
          fsm_next.cmd                            <= DREC_I(7 downto IrLength);
          fsm_next.address(7 downto IrLength)     <= (others => '0');
          fsm_next.address(IrLength - 1 downto 0) <= DREC_I(IrLength - 1 downto 0);
          fsm_next.state                          <= st_length;
        elsif (msg_timer = MSG_TIMEOUT) then
          fsm_next.state <= st_idle;
        end if;

      when st_length =>
        fsm_next.state <= st_length;
        run_timer      <= '1';

        if (RX_EMPTY_I = '0') then
          fsm_next.re <= '1';
        else
          fsm_next.re <= '0';
        end if;

        if (fsm.re = '1') then
          fsm_next.data_length <= to_integer(unsigned(DREC_I));
          fsm_next.byte_count  <= 0;

          case fsm.cmd is

            when CMD_READ =>
              if (fsm.address = ADDR_DMI) then
                fsm_next.state <= st_wait_read_dmi;
              else
                fsm_next.state <= st_read;
              end if;

            when CMD_WRITE =>
              fsm_next.state <= st_write;

            when CMD_RW =>
              if (fsm.address = ADDR_DMI) then
                fsm_next.state <= st_wait_read_dmi;
              else
                fsm_next.state <= st_rw;
              end if;

            when CMD_RESET =>
              fsm_next.state <= st_reset;

            when others =>
              fsm_next.state <= st_idle;

          end case;

        elsif (msg_timer = MSG_TIMEOUT) then
          fsm_next.state <= st_idle;
        end if;

      when st_wait_read_dmi =>
        fsm_next.state <= st_wait_read_dmi;

        if (DMI_READ_VALID_I = '0' and fsm.dmi_read_ready = '0') then
          fsm_next.dmi_read_ready <= '1';
        elsif (DMI_READ_VALID_I = '1' and fsm.dmi_read_ready = '1') then
          fsm_next.dmi            <= dmi_resp_to_stl(DMI_READ_I);
          fsm_next.dmi_read_ready <= '0';

          case fsm.cmd is

            when CMD_READ =>
              fsm_next.state <= st_read;

            when CMD_RW =>
              fsm_next.state <= st_rw;

            when others =>
              fsm_next.state <= st_idle;

          end case;

        end if;

      when st_read =>
        fsm_next.address <= fsm.address;
        fsm_next.state   <= st_read;
        fsm_next.we      <= TX_READY_I;
        run_timer        <= '1';

        if (TX_READY_I = '1') then
          fsm_next.byte_count <= fsm.byte_count + 1;
        else
          fsm_next.byte_count <= fsm.byte_count;
        end if;

        if (msg_timer < MSG_TIMEOUT) then

          case fsm.address is

            when ADDR_IDCODE =>
              read_register (
                value        => IDCODEVALUE,
                state_after  => st_idle,
                fsm_i        => fsm,
                fsm_next_i   => fsm_next);

            when ADDR_DTMCS =>
              read_register (
                value        => fsm.dtmcs,
                state_after  => st_idle,
                fsm_i        => fsm,
                fsm_next_i   => fsm_next);

            when ADDR_DMI =>
              read_register (
                value        => fsm.dmi,
                state_after  => st_idle,
                fsm_i        => fsm,
                fsm_next_i   => fsm_next);

            when others =>
              fsm_next.data_send <= (others => '0');
              fsm_next.state     <= st_idle;

          end case;

        else
          fsm_next.state <= st_idle;
        end if;

      when st_write =>
        fsm_next.state      <= st_write;
        run_timer           <= '1';
        fsm_next.byte_count <= fsm.byte_count;

        if (fsm.re = '1') then
          fsm_next.byte_count <= fsm.byte_count + 1;
        end if;

        if (msg_timer < MSG_TIMEOUT) then

          case fsm.address is

            when ADDR_DTMCS =>               -- Write to dtmcs
              write_register (
                  target       => fsm.dtmcs,
                  target_next  => fsm_next.dtmcs,
                  rx_empty     => RX_EMPTY_I,
                  data_read    => DREC_I,
                  fsm_i        => fsm,
                  fsm_next_i   => fsm_next,
                  state_after  => st_idle);

            when ADDR_DMI =>
              write_register (
                  target       => fsm.dmi,
                  target_next  => fsm_next.dmi,
                  rx_empty     => RX_EMPTY_I,
                  data_read    => DREC_I,
                  fsm_i        => fsm,
                  fsm_next_i   => fsm_next,
                  state_after  => st_wait_write_dmi);

            when others =>
              fsm_next.state <= st_idle;

          end case;

        else
          fsm_next.state <= st_idle;
        end if;

      when st_wait_write_dmi =>
        fsm_next.state <= st_wait_write_dmi;
        write_dmi (
          dmi_req_next => fsm_next.dmi_write,
          ready        => DMI_WRITE_READY_I,
          valid_next   => fsm_next.dmi_write_valid,
          dmi_i        => fsm.dmi);

        if (fsm.dmi_write_valid = '1' and DMI_WRITE_READY_I = '1') then
          fsm_next.state <= st_idle;
        end if;

      when st_rw =>
        fsm_next.state <= st_rw;
        run_timer      <= '1';

        if (TX_READY_I = '1' and RX_EMPTY_I = '0') then
          fsm_next.we         <= '1';
          fsm_next.re         <= '1';
          fsm_next.byte_count <= fsm.byte_count + 1;
        else
          fsm_next.we         <= '1';
          fsm_next.re         <= '1';
          fsm_next.byte_count <= fsm.byte_count;
        end if;

        if (msg_timer < MSG_TIMEOUT) then

          case fsm.address is

            when ADDR_IDCODE =>
              read_register (
                value        => IDCODE,
                state_after  => st_idle,
                fsm_i        => fsm,
                fsm_next_i   => fsm_next);

            when ADDR_DTMCS =>
              read_register (
                value        => fsm.dtmcs,
                state_after  => st_idle,
                fsm_i        => fsm,
                fsm_next_i   => fsm_next);
              write_register (
                target       => fsm.dtmcs,
                target_next  => fsm_next.dtmcs,
                rx_empty     => RX_EMPTY_I,
                data_read    => DREC_I,
                fsm_i        => fsm,
                fsm_next_i   => fsm_next,
                state_after  => st_idle);

            when ADDR_DMI =>
              read_register (
                value        => fsm.dmi,
                state_after  => st_wait_write_dmi,
                fsm_i        => fsm,
                fsm_next_i   => fsm_next);
              write_register (
                target       => fsm.dmi,
                target_next  => fsm_next.dmi,
                data_read    => DREC_I,
                rx_empty     => RX_EMPTY_I,
                fsm_i        => fsm,
                fsm_next_i   => fsm_next,
                state_after  => st_wait_write_dmi);

            when others =>
              fsm_next.data_send <= (others => '0');

              if (fsm.address = ADDR_DMI) then
                fsm_next.state <= st_wait_write_dmi;
              else
                fsm_next.state <= st_idle;
              end if;

          end case;

        else
          fsm_next.state <= st_idle;
        end if;

      when st_reset =>
        fsm_next.state      <= st_idle;
        fsm_next.byte_count <= 0;
        fsm_next.re         <= '0';
        fsm_next.we         <= '0';
        fsm_next.address    <= ADDR_IDCODE;
        fsm_next.dtmcs      <= (others => '0');
        fsm_next.dmi        <= (others => '0');
        -- Trigger Reset of DMI module.
        DMI_RESET_O <= '1';
        run_timer   <= '0';

    end case;

  end process FSM_COMB;

end architecture BEHAVIORAL;
