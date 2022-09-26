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
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library WORK;
  use work.uart_pkg.all;

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
    st_read,
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
    address         : std_logic_vector(IrLength - 1 downto 0);
    cmd             : std_logic_vector(2 downto 0);
    data_length     : unsigned (7 downto 0);
    -- FSM Signals
    state : state_t;
  end record fsm_t;

  signal fsm,         fsm_next                                                    : fsm_t;

  -- Time Out timer to catch unfished operations.
  -- Each UART-Frame takes 10 baud periods (1 Start + 8 Data + 1 Stop)
  -- Wait for the time of 5 UART-Frames.
  constant msg_timeout                                                            : integer := 5 * (10 * CLK_RATE / BAUD_RATE);
  signal   msg_timer                                                              : integer range 0 to msg_timeout;
  signal   run_timer, timer_overflow                                              : std_logic;
  -- Number of (paritial) bytes required to save largest register.
  -- Largest register is DMI, therefore ceil(DMI'length/8) bytes are
  -- necessary.
  constant max_bytes                                                              : integer := (DMI_REQ_LENGTH + 7) / 8;

  signal ser_run,     ser_done                                                    : std_logic;
  signal ser_data_in                                                              : std_logic_vector(7 downto 0);
  signal ser_data_out                                                             : std_logic_vector(7 downto 0);
  signal ser_reg_out                                                              : std_logic_vector(max_bytes * 8 - 1 downto 0);
  signal ser_reg_in                                                               : std_logic_vector(max_bytes * 8 - 1 downto 0);
  signal ser_num_bits                                                             : unsigned(7 downto 0);

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

  -- FSM states to output
  DMI_WRITE_VALID_O <= fsm.dmi_write_valid;
  DMI_WRITE_O       <= fsm.dmi_write;
  DMI_READ_READY_O  <= fsm.dmi_read_ready;

  DSEND_O <= fsm.data_send;
  WE_O    <= fsm.we;
  RE_O    <= fsm.re;

  -- De/Serializer entities for different registers.
  DE_SERIALIZER_1 : entity work.de_serializer
    generic map (
    -- The largest register is DMI with 41 bytes.
      MAX_BYTES => (DMI_REQ_LENGTH + 7) / 8
    )
    port map (
      CLK      => CLK,
      RST      => RST,
      NUM_BITS => ser_num_bits,
      D_I      => DREC_I,
      D_O      => fsm.data_send,
      REG_I    => ser_reg_in,
      REG_O    => ser_reg_out,
      RUN_I    => ser_run,
      DONE_O   => ser_done
    );

  TIMEOUT : process (CLK) is
  begin

    if rising_edge(CLK) then
      -- Timer resets if either no message is in flight (run_timer = 0)
      -- or new data is in the RX-Fifo.
      if (RST = '1' or run_timer = '0' or RX_EMPTY_I = '0') then
        msg_timer      <= 0;
        timer_overflow <= '0';
      else
        msg_timer <= msg_timer + 1;
        if (msg_timer = msg_timeout) then
          timer_overflow <= '1';
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
        fsm.address         <= ADDR_IDCODE;
        fsm.cmd             <= CMD_NOP;

        DTMCS_SELECT_O <= '0';
        fsm.dtmcs      <= dtmcs_to_stl(DTMCS_ZERO);
        fsm.state      <= st_idle;
        ser_run            <= '0';
      else
        fsm <= fsm_next;
        -- Only bits 17 and 16 of dtmcs are writable.
        -- Discard the rest.
        -- fsm.dtmcs           <= dtmcs_to_stl(DTMCS_ZERO);
        fsm.dtmcs(17 downto 16) <= fsm_next.dtmcs(17 downto 16);
        -- Signal that DTMCS has been selected.
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
        -- Reset some signals to defaults.
        fsm_next.we              <= '0';
        fsm_next.data_send       <= (others => '0');
        fsm_next.dmi_write_valid <= '0';
        fsm_next.dmi_write       <= (addr => (others => '0'), data => (others => '0'), op => (others => '0'));
        fsm_next.dmi_read_ready  <= '0';

        fsm_next.cmd <= CMD_NOP;

        DMI_RESET_O <= '0';

        -- No message in flight.
        run_timer <= '0';

        -- Without data to read, remain in idle state.
        if (RX_EMPTY_I = '0') then
          fsm_next.re    <= '1';
          fsm_next.state <= st_header;
        else
          fsm_next.re    <= '0';
          fsm_next.state <= st_idle;
        end if;

      when st_header =>
        -- Is the byte from RX fifo equal to our header?
        if (DREC_I = HEADER) then
          -- If yes, proceed to CmdAddr.
          fsm_next.state <= st_cmdaddr;
        else
          -- otherwise back to idle.
          fsm_next.state <= st_idle;
        end if;

      when st_cmdaddr =>
        -- Message is in flight. Run the timer to catch a message
        -- timeout.
        run_timer <= '1';

        -- Trigger reading of a byte from RX fifo.
        if (RX_EMPTY_I = '0') then
          fsm_next.re <= '1';
        else
          fsm_next.re <= '0';
        end if;

        -- Have we read a byte from RX fifo?
        if (fsm.re = '1') then
          -- If yes, decode into command and address.
          fsm_next.cmd     <= DREC_I(7 downto IrLength);
          fsm_next.address <= DREC_I(IrLength - 1 downto 0);
          -- Move to next state.
          fsm_next.state <= st_length;
        else
          -- Have we hit the message timeout? If yes, back to idle.
          if (timer_overflow = '1') then
            fsm_next.state <= st_idle;
          end if;
        end if;

      when st_length =>
        -- Trigger reading of a byte from RX fifo.
        if (RX_EMPTY_I = '0') then
          fsm_next.re <= '1';
        else
          fsm_next.re <= '0';
        end if;

        -- Have we read a byte from RX fifo?
        if (fsm.re = '1') then
          -- Apply byte as unsigned integer to data_length.
          fsm_next.data_length <= unsigned(DREC_I);

          -- Move on to the next state determined by command.
          case fsm.cmd is

            when CMD_READ =>
              fsm_next.state <= st_read;

            when CMD_WRITE =>
              fsm_next.state <= st_write;

            when CMD_RW =>
              fsm_next.state <= st_rw;

            when CMD_RESET =>
              fsm_next.state <= st_reset;

            when others =>
              fsm_next.state <= st_idle;

          end case;

        else
          -- Have we hit the message timeout? If yes, back to idle.
          if (timer_overflow = '1') then
            fsm_next.state <= st_idle;
          end if;
        end if;

      when st_read =>
        -- A message with read-command is finished after length byte.
        run_timer <= '0';
        -- Always write when TX is ready.
        fsm_next.we <= TX_READY_I;

        case fsm.address is

          -- Dependent on address, load up the serializers register input
          -- with the appropriate data.
          when ADDR_IDCODE =>
            -- IDCODE Register has 32 bits.
            ser_num_bits                                                <= to_unsigned(32, 8);
            ser_reg_in(ser_reg_in'length - 1 downto IDCODEVALUE'length) <= (others => '0');
            ser_reg_in(IDCODEVALUE'length - 1 downto 0)                 <= IDCODEVALUE;
            ser_run                                                     <= fsm_next.we;

          when ADDR_DTMCS =>
            ser_num_bits                                              <= to_unsigned(fsm.dtmcs'length, 8);
            ser_reg_in(ser_reg_in'length - 1 downto fsm.dtmcs'length) <= (others => '0');
            ser_reg_in(fsm.dtmcs'length - 1 downto 0)                 <= fsm.dtmcs;
            ser_run                                                   <= fsm_next.we;

          when ADDR_DMI =>
            ser_num_bits                                            <= to_unsigned(fsm.dmi'length, 8);
            ser_reg_in(ser_reg_in'length - 1 downto fsm.dmi'length) <= (others => '0');
            ser_reg_in(fsm.dmi'length - 1 downto 0)                 <= fsm.dmi;
            ser_run                                                 <= fsm_next.we;

          when others =>
            fsm_next.data_send <= (others => '0');
            fsm_next.state     <= st_idle;

        end case;

        if (ser_done = '1') then
          -- We are done sending if our serializer is done.
          -- ToDo: Wait for DMI done signal
          fsm_next.state <= st_idle;
        end if;

      when st_write =>

        -- Always read when rx-fifo is not empty:
        if (RX_EMPTY_I = '0') then
          fsm_next.re <= '1';
        else
          fsm_next.re <= '0';
        end if;

        case fsm.address is

          -- Address decides into which register DREC_I is serialized into.
          when ADDR_DTMCS =>
            ser_num_bits   <= to_unsigned(fsm.dtmcs'length, 8);
            fsm_next.dtmcs <= ser_reg_out;
            ser_run        <= fsm_next.re;

          when ADDR_DMI =>
            ser_num_bits <= to_unsigned(fsm.dmi'length, 8);
            fsm_next.dmi <= ser_reg_out;
            ser_run      <= fsm_next.re;

          when others =>
            fsm_next.state <= st_idle;

        end case;

        if (timer_overflow = '1' or ser_done = '1') then
          -- Writing is done, if either our serializer is done or message
          -- timeout is reached.
          -- ToDo: Wait for dmi.
          fsm_next.state <= st_idle;
        end if;

      when st_rw =>
        -- Read and write is performed simultaneously. Requires TX to be both
        -- ready to send and RX-Fifo to be not empty.
        if (TX_READY_I = '1' and RX_EMPTY_I = '0') then
          fsm_next.we <= '1';
          fsm_next.re <= '1';
        else
          fsm_next.we <= '0';
          fsm_next.re <= '0';
        end if;

        if (msg_timer < msg_timeout) then

          case fsm.address is

            when ADDR_IDCODE =>
              -- IDCODE is read-only.
              ser_num_bits                                                <= to_unsigned(32, 8);
              ser_reg_in(ser_reg_in'length - 1 downto IDCODEVALUE'length) <= (others => '0');
              ser_reg_in(IDCODEVALUE'length - 1 downto 0)                 <= IDCODEVALUE;
              ser_run                                                     <= fsm_next.we;

            when ADDR_DTMCS =>
              ser_num_bits                                              <= to_unsigned(fsm.dtmcs'length, 8);
              ser_reg_in(ser_reg_in'length - 1 downto fsm.dtmcs'length) <= (others => '0');
              ser_reg_in(fsm.dtmcs'length - 1 downto 0)                 <= fsm.dtmcs;
              fsm_next.dtmcs                                            <= ser_reg_out;
              ser_run                                                   <= fsm_next.we;

            when ADDR_DMI =>
              ser_num_bits                                            <= to_unsigned(fsm.dmi'length, 8);
              ser_reg_in(ser_reg_in'length - 1 downto fsm.dmi'length) <= (others => '0');
              ser_reg_in(fsm.dmi'length - 1 downto 0)                 <= fsm.dmi;
              fsm_next.dmi                                            <= ser_reg_out;
              ser_run                                                 <= fsm_next.we;

            when others =>
              fsm_next.data_send <= (others => '0');
              fsm_next.state     <= st_idle;

          end case;

        else
          fsm_next.state <= st_idle;
        end if;

      when st_reset =>
        fsm_next.state      <= st_idle;
        fsm_next.re         <= '0';
        fsm_next.we         <= '0';
        fsm_next.address    <= ADDR_IDCODE;
        fsm_next.dtmcs      <= (others => '0');
        fsm_next.dmi        <= (others => '0');
        -- Trigger Reset of DMI module.
        DMI_RESET_O <= '1';
        run_timer   <= '0';
        ser_run     <= '0';

    end case;

  end process FSM_COMB;

end architecture BEHAVIORAL;
