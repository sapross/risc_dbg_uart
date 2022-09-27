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
    CLK                   : in    std_logic;
    RST                   : in    std_logic;
    -- UART-Interface connections
    RE_O                  : out   std_logic;
    WE_O                  : out   std_logic;
    TX_READY_I            : in    std_logic;
    RX_EMPTY_I            : in    std_logic;
    RX_FULL_I             : in    std_logic;
    DSEND_O               : out   std_logic_vector(7 downto 0);
    DREC_I                : in    std_logic_vector(7 downto 0);

    -- JTAG is interested in writing the DTM CSR register
    DTMCS_SELECT_O        : out   std_logic;
    -- clear error state
    DMI_RESET_O           : out   std_logic;
    DMI_ERROR_I           : in    std_logic_vector(1 downto 0);

    -- Signals towards debug module interface
    DMI_READ_O            : out   std_logic;
    DMI_WRITE_O           : out   std_logic;
    DMI_O                 : out   std_logic_vector(DMI_REQ_LENGTH - 1 downto 0);
    DMI_I                 : in    std_logic_vector(DMI_REQ_LENGTH - 1 downto 0);
    DMI_DONE_I            : in    std_logic
  );
end entity DMI_UART_TAP;

architecture BEHAVIORAL of DMI_UART_TAP is

  type state_t is (
    st_idle,
    st_cmdaddr,
    st_header,
    st_length,
    st_read,
    st_write,
    st_rw,
    st_reset
  );

  type fsm_t is record
    dmi   : std_logic_vector(DMI_REQ_LENGTH - 1 downto 0);
    dtmcs : std_logic_vector(31 downto 0);
    -- FSM Signals
    state       : state_t;
    address     : std_logic_vector(IrLength - 1 downto 0);
    cmd         : std_logic_vector(2 downto 0);
    data_length : unsigned (7 downto 0);
  end record fsm_t;

  -- UART-Interface signals
  signal re               : std_logic;
  signal we               : std_logic;
  -- DMI-Interace Signals
  constant MAX_BYTES      : integer := (DMI_REQ_LENGTH + 7) / 8;
  signal   dtmcs_select   : std_logic;
  signal   dmi_reset      : std_logic;
  signal   dmi_read       : std_logic;
  signal   dmi_write      : std_logic;
  -- Signals for the De-/Serializer
  signal ser_reset        : std_logic;
  signal ser_run          : std_logic;
  signal ser_done         : std_logic;
  signal ser_num_bits     : unsigned(7 downto 0);
  signal ser_data_in      : std_logic_vector(7 downto 0);
  signal ser_reg_in       : std_logic_vector(MAX_BYTES * 8 - 1 downto 0);
  signal ser_reg_out      : std_logic_vector(MAX_BYTES * 8 - 1 downto 0);
  -- State machine and combinatorial next state.
  signal fsm, fsm_next    : fsm_t;

  -- Time Out timer to catch unfished operations.
  -- Each UART-Frame takes 10 baud periods (1 Start + 8 Data + 1 Stop)
  -- Wait for the time of 5 UART-Frames.
  constant MSG_TIMEOUT    : integer := 5 * (10 * CLK_RATE / BAUD_RATE);
  signal   msg_timer      : integer range 0 to MSG_TIMEOUT;
  signal   timer_overflow : std_logic;
  -- Number of (partial) bytes required to save largest register.
  -- Largest register is DMI, therefore ceil(DMI'length/8) bytes are
  -- necessary.

  -- purpose: Signals timer to run dependent on state. Simplifies if-condition.

  function run_timer (
    signal state_i : state_t;
    signal rx_empty_i : std_logic)
    return boolean is
  begin  -- function run_timer

    -- Run timer only if RX-Fifo is empty and we are in an ongoing transaction.
    if (rx_empty_i = '1' and (
        state_i = st_cmdaddr or
        state_i = st_length or
        state_i = st_write or
        state_i = st_rw)) then
      return true;
    else
      return false;
    end if;

  end function run_timer;

begin

  -- FSM states to output
  DTMCS_SELECT_O <= dtmcs_select;
  DMI_RESET_O    <= dmi_reset;
  DMI_READ_O     <= dmi_read;
  DMI_WRITE_O    <= dmi_write;
  DMI_O          <= fsm.dmi;

  WE_O <= we;
  RE_O <= re;

  -- De/Serializer entities for different registers.
  DE_SERIALIZER_1 : entity work.de_serializer
    generic map (
      -- The largest register is DMI with 41 bytes.
      MAX_BYTES => (DMI_REQ_LENGTH + 7) / 8
    )
    port map (
      CLK => CLK,
      -- Synchronous reset may also be triggered by reset command.
      RST        => RST or ser_reset,
      NUM_BITS_I => ser_num_bits,
      D_I        => DREC_I,
      D_O        => DSEND_O,
      REG_I      => ser_reg_in,
      REG_O      => ser_reg_out,
      RUN_I      => ser_run,
      DONE_O     => ser_done
    );

  TIMEOUT : process (CLK) is
  begin

    if rising_edge(CLK) then
      -- Timer resets if either no message is in flight (run_timer = 0)
      -- or new data is in the RX-Fifo.
      if (RST = '1' or not run_timer(fsm.state, RX_EMPTY_I)) then
        msg_timer      <= 0;
        timer_overflow <= '0';
      else
        msg_timer <= msg_timer + 1;
        if (msg_timer = MSG_TIMEOUT) then
          timer_overflow <= '1';
        end if;
      end if;
    end if;

  end process TIMEOUT;

  FSM_CORE : process (CLK) is
  begin

    if rising_edge(CLK) then
      if (RST = '1') then
        -- FSM Signals
        fsm.dmi         <= (others => '0');
        fsm.dtmcs       <= dtmcs_to_stl(DTMCS_ZERO);
        fsm.state       <= st_idle;
        fsm.address     <= ADDR_IDCODE;
        fsm.cmd         <= CMD_NOP;
        fsm.data_length <= (others => '0');
      else
        fsm <= fsm_next;
        -- Only bits 17 and 16 of dtmcs are writable. Discard the rest.
        fsm.dtmcs(17 downto 16) <= fsm_next.dtmcs(17 downto 16);
      end if;
    end if;

  end process FSM_CORE;

  FSM_COMB : process (fsm, DREC_I, RX_EMPTY_I, TX_READY_I, DMI_I, DMI_DONE_I, ser_done, msg_timer) is
  begin

    fsm_next <= fsm;

    -- UART-Interface signals
    re <= '0';
    we <= '0';
    -- DMI-Interace Signals
    dtmcs_select <= '0';
    dmi_reset    <= '0';
    dmi_read     <= '0';
    dmi_write    <= '0';

    -- Signals for the De-/Serializer
    ser_reset    <= '1';
    ser_run      <= '0';
    ser_data_in  <= (others => '0');
    ser_reg_in   <= (others => '0');
    ser_num_bits <= to_unsigned(1, 8);

    case fsm.state is

      when st_idle =>
        -- FSM Signals
        fsm_next.cmd         <= CMD_NOP;
        fsm_next.data_length <= (others => '0');

        -- Without data to read, remain in idle state.
        if (RX_EMPTY_I = '0') then
          fsm_next.state <= st_header;
        else
          fsm_next.state <= st_idle;
        end if;
      when st_header =>
        if (RX_EMPTY_I = '0') then
          re <= '1';
          -- Is the byte from RX fifo equal to our header?
          if (DREC_I = HEADER) then
            -- If yes, proceed to CmdAddr.
            fsm_next.state <= st_cmdaddr;
          end if;
        else
          re <= '0';
        end if;

      when st_cmdaddr =>
        -- Trigger reading of a byte from RX fifo.
        if (RX_EMPTY_I = '0') then
          re <= '1';
          -- Decode into command and address.
          fsm_next.cmd     <= DREC_I(7 downto IrLength);
          fsm_next.address <= DREC_I(IrLength - 1 downto 0);
          -- Move to next state.
          fsm_next.state <= st_length;
        else
          re <= '0';
          -- Have we hit the message timeout? If yes, back to idle.
          if (timer_overflow = '1') then
            fsm_next.state <= st_idle;
          end if;
        end if;

      when st_length =>
        -- Trigger reading of a byte from RX fifo.
        if (RX_EMPTY_I = '0') then
          re <= '1';
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
          re <= '0';
          -- Have we hit the message timeout? If yes, back to idle.
          if (timer_overflow = '1') then
            fsm_next.state <= st_idle;
          end if;
        end if;

      when st_read =>
        ser_reset <= '0';
        -- Always write when TX is ready.
        if (ser_done = '0') then
          if (TX_READY_I = '1') then
            we      <= '1';
            ser_run <= '1';

            case fsm.address is

              -- Dependent on address, load up the serializers register input
              -- with the appropriate data.
              when ADDR_IDCODE =>
                ser_reg_in(ser_reg_in'length - 1 downto IDCODEVALUE'length) <= (others => '0');
                ser_reg_in(IDCODEVALUE'length - 1 downto 0)                 <= IDCODEVALUE;
                -- IDCODE Register has 32 bits.
                ser_num_bits <= to_unsigned(32, 8);

              when ADDR_DTMCS =>
                ser_reg_in(ser_reg_in'length - 1 downto fsm.dtmcs'length) <= (others => '0');
                ser_reg_in(fsm.dtmcs'length - 1 downto 0)                 <= fsm.dtmcs;

                ser_num_bits <= to_unsigned(fsm.dtmcs'length, 8);

              when ADDR_DMI =>

                ser_reg_in(ser_reg_in'length - 1 downto fsm.dmi'length) <= (others => '0');
                ser_reg_in(fsm.dmi'length - 1 downto 0)                 <= fsm.dmi;

                ser_num_bits <= to_unsigned(fsm.dmi'length, 8);

              when others =>
                fsm_next.state <= st_idle;

            end case;

          else
            we      <= '0';
            ser_run <= '0';
          end if;
        else
          -- We are done sending if our serializer is done.
          -- ToDo: Wait for DMI done signal
          fsm_next.state <= st_idle;
        end if;

      when st_write =>

        ser_reset <= '0';
        -- Always read when rx-fifo is not empty and serialization not done:
        if (timer_overflow = '0' and ser_done = '0') then
          if (RX_EMPTY_I = '0') then
            re      <= '1';
            ser_run <= '1';

            case fsm.address is

              -- Address decides into which register DREC_I is serialized into.
              when ADDR_DTMCS =>
                ser_num_bits   <= to_unsigned(fsm.dtmcs'length, 8);
                fsm_next.dtmcs <= ser_reg_out(fsm.dtmcs'length - 1 downto 0);

              when ADDR_DMI =>
                dmi_write <= '1';
                ser_num_bits <= to_unsigned(fsm.dmi'length, 8);
                fsm_next.dmi <= ser_reg_out(fsm.dmi'length - 1 downto 0);

              when others =>
                fsm_next.state <= st_idle;
                ser_reset      <= '1';

            end case;

          else
            re      <= '0';
            ser_run <= '0';
          end if;
        else
          -- Writing is done, if either our serializer is done or message
          -- timeout is reached.
          -- ToDo: Wait for dmi.
          fsm_next.state <= st_idle;
        end if;

      when st_rw =>
        ser_reset <= '0';
        -- Read and write is performed simultaneously. Requires TX to be both
        -- ready to send, RX-Fifo to be not empty and serialization to be not
        -- done.
        if (timer_overflow = '0' and ser_done = '0') then
          if (TX_READY_I = '1' and RX_EMPTY_I = '0') then
            we      <= '1';
            re      <= '1';
            ser_run <= '1';

            case fsm.address is

              when ADDR_IDCODE =>
                -- IDCODE is read-only.
                ser_reg_in(ser_reg_in'length - 1 downto IDCODEVALUE'length) <= (others => '0');

                ser_num_bits                                <= to_unsigned(32, 8);
                ser_reg_in(IDCODEVALUE'length - 1 downto 0) <= IDCODEVALUE;

              when ADDR_DTMCS =>
                ser_reg_in(ser_reg_in'length - 1 downto fsm.dtmcs'length) <= (others => '0');

                ser_num_bits                              <= to_unsigned(fsm.dtmcs'length, 8);
                ser_reg_in(fsm.dtmcs'length - 1 downto 0) <= fsm.dtmcs;
                fsm_next.dtmcs                            <= ser_reg_out(fsm.dtmcs'length - 1 downto 0);

              when ADDR_DMI =>
                ser_reg_in(ser_reg_in'length - 1 downto fsm.dmi'length) <= (others => '0');

                ser_num_bits                            <= to_unsigned(fsm.dmi'length, 8);
                ser_reg_in(fsm.dmi'length - 1 downto 0) <= fsm.dmi;
                fsm_next.dmi                            <= ser_reg_out(fsm.dmi'length - 1 downto 0);

              when others =>
                fsm_next.state <= st_idle;

            end case;

          else
            we      <= '0';
            re      <= '0';
            ser_run <= '0';
          end if;
        else
          fsm_next.state <= st_idle;
        end if;

      when st_reset =>
        fsm_next.state   <= st_idle;
        re               <= '0';
        we               <= '0';
        fsm_next.address <= ADDR_IDCODE;
        -- ToDo: correct dtmcs clear value
        fsm_next.dtmcs <= (others => '0');
        fsm_next.dmi   <= (others => '0');
        -- Trigger reset for DMI module and de-/serializer.
        dmi_reset <= '1';
        -- Stop serialization.
        ser_reset <= '1';
        ser_run   <= '0';

    end case;

  end process FSM_COMB;

end architecture BEHAVIORAL;
