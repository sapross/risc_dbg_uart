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

    -- Signals towards debug module interface
    DMI_READ_O        : out   std_logic;
    DMI_WRITE_O       : out   std_logic;
    DMI_O             : out   std_logic_vector(DMI_REQ_LENGTH - 1 downto 0);
    DMI_I             : in    std_logic_vector(DMI_REQ_LENGTH - 1 downto 0);
    DONE_O            : in    std_logic
  );
end entity DMI_UART_TAP;

architecture BEHAVIORAL of DMI_UART_TAP is

  constant MAX_BYTES                                                              : integer := (DMI_REQ_LENGTH + 7) / 8;

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
    re : std_logic;
    we : std_logic;
    -- DMI-Interace Signals
    dtmcs_select : std_logic;
    dmi_reset    : std_logic;
    dmi_read     : std_logic;
    dmi_write    : std_logic;
    dmi          : std_logic_vector(DMI_REQ_LENGTH - 1 downto 0);
    dtmcs        : std_logic_vector(31 downto 0);
    -- Signals for the De-/Serializer
    ser_reset    : std_logic;
    ser_run      : std_logic;
    ser_data_in  : std_logic_vector(7 downto 0);
    ser_reg_in   : std_logic_vector(MAX_BYTES * 8 - 1 downto 0);
    ser_num_bits : unsigned(7 downto 0);
    -- FSM Signals
    state       : state_t;
    address     : std_logic_vector(IrLength - 1 downto 0);
    cmd         : std_logic_vector(2 downto 0);
    data_length : unsigned (7 downto 0);
  end record fsm_t;

  -- State machine and combinatorial next state.
  signal fsm, fsm_next                                                            : fsm_t;

  -- Byte to transmit via TX
  signal data_send                                                                : std_logic_vector(7 downto 0);
  -- Time Out timer to catch unfished operations.
  -- Each UART-Frame takes 10 baud periods (1 Start + 8 Data + 1 Stop)
  -- Wait for the time of 5 UART-Frames.
  constant MSG_TIMEOUT                                                            : integer := 5 * (10 * CLK_RATE / BAUD_RATE);
  signal   msg_timer                                                              : integer range 0 to MSG_TIMEOUT;
  signal   timer_overflow                                                         : std_logic;
  -- Number of (partial) bytes required to save largest register.
  -- Largest register is DMI, therefore ceil(DMI'length/8) bytes are
  -- necessary.

  signal ser_done                                                                 : std_logic;
  signal ser_reg_out                                                              : std_logic_vector(MAX_BYTES * 8 - 1 downto 0);

  -- purpose: Signals timer to run dependent on state. Simplifies if-condition.

  function run_timer (
    signal state_i : state_t;
    signal rx_empty_i : std_logic)
    return boolean is
  begin  -- function run_timer

    -- Run timer only if RX-Fifo is empty and we are in an ongoing transaction.
    if (rx_empty_i = '1' or
        state_i = st_cmdaddr or
        state_i = st_length or
        state_i = st_write or
        state_i = st_rw) then
      return true;
    else
      return false;
    end if;

  end function run_timer;

begin

  -- FSM states to output
  DTMCS_SELECT_O <= fsm.dtmcs_select;
  DMI_RESET_O    <= fsm.dmi_reset;
  DMI_READ_O     <= fsm.dmi_read;
  DMI_WRITE_O    <= fsm.dmi_write;
  DMI_O          <= fsm.dmi;

  DSEND_O <= data_send;
  WE_O    <= fsm.we;
  RE_O    <= fsm.re;

  -- De/Serializer entities for different registers.
  DE_SERIALIZER_1 : entity work.de_serializer
    generic map (
      -- The largest register is DMI with 41 bytes.
      MAX_BYTES => (DMI_REQ_LENGTH + 7) / 8
    )
    port map (
      CLK => CLK,
      -- Synchronous reset may also be triggered by reset command.
      RST        => RST or fsm.ser_reset,
      NUM_BITS_I => fsm.ser_num_bits,
      D_I        => DREC_I,
      D_O        => data_send,
      REG_I      => fsm.ser_reg_in,
      REG_O      => ser_reg_out,
      RUN_I      => fsm.ser_run,
      DONE_O     => ser_done
    );

  TIMEOUT : process (CLK) is
  begin

    if rising_edge(CLK) then
      -- Timer resets if either no message is in flight (run_timer = 0)
      -- or new data is in the RX-Fifo.
      if (RST = '1' or run_timer(fsm.state, RX_EMPTY_I)) then
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
        -- UART-Interface signals
        fsm.re <= '0';
        fsm.we <= '0';
        -- DMI-Interace Signals
        fsm.dtmcs_select <= '0';
        fsm.dmi_reset    <= '0';
        fsm.dmi_read     <= '0';
        fsm.dmi_write    <= '0';
        fsm.dmi          <= (others => '0');
        fsm.dtmcs        <= dtmcs_to_stl(DTMCS_ZERO);
        -- Signals for the De-/Serializer
        fsm.ser_run      <= '0';
        fsm.ser_reset    <= '0';
        fsm.ser_data_in  <= (others => '0');
        fsm.ser_reg_in   <= (others => '0');
        fsm.ser_num_bits <= to_unsigned(1, 8);
        -- FSM Signals
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

  FSM_COMB : process (fsm, DREC_I, RX_EMPTY_I, TX_READY_I, DMI_I, DONE_O,ser_done, msg_timer) is
  begin

    fsm_next <= fsm;

    case fsm.state is

      when st_idle =>
        -- UART-Interface signals
        fsm_next.re <= '0';
        fsm_next.we <= '0';
        -- DMI-Interace Signals
        fsm_next.dtmcs_select <= '0';
        fsm_next.dmi_reset    <= '0';
        fsm_next.dmi_read     <= '0';
        fsm_next.dmi_write    <= '0';

        -- Signals for the De-/Serializer
        fsm_next.ser_reset    <= '0';
        fsm_next.ser_run      <= '0';
        fsm_next.ser_data_in  <= (others => '0');
        fsm_next.ser_reg_in   <= (others => '0');
        fsm_next.ser_num_bits <= to_unsigned(1, 8);
        -- FSM Signals
        fsm_next.cmd         <= CMD_NOP;
        fsm_next.data_length <= (others => '0');

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
        -- Always write when TX is ready.
        if (TX_READY_I = '1' and ser_done = '0') then
          fsm_next.we      <= '1';
          fsm_next.ser_run <= '1';
        else
          fsm_next.we      <= '0';
          fsm_next.ser_run <= '0';
        end if;

        if (ser_done = '0') then

          case fsm.address is

            -- Dependent on address, load up the serializers register input
            -- with the appropriate data.
            when ADDR_IDCODE =>
              fsm_next.ser_reg_in(fsm.ser_reg_in'length - 1 downto IDCODEVALUE'length) <= (others => '0');
              -- IDCODE Register has 32 bits.
              fsm_next.ser_num_bits                                <= to_unsigned(32, 8);
              fsm_next.ser_reg_in(IDCODEVALUE'length - 1 downto 0) <= IDCODEVALUE;

            when ADDR_DTMCS =>
              fsm_next.ser_reg_in(fsm.ser_reg_in'length - 1 downto fsm.dtmcs'length) <= (others => '0');

              fsm_next.ser_num_bits                              <= to_unsigned(fsm.dtmcs'length, 8);
              fsm_next.ser_reg_in(fsm.dtmcs'length - 1 downto 0) <= fsm.dtmcs;

            when ADDR_DMI =>
              fsm_next.ser_reg_in(fsm.ser_reg_in'length - 1 downto fsm.dmi'length) <= (others => '0');

              fsm_next.ser_num_bits                            <= to_unsigned(fsm.dmi'length, 8);
              fsm_next.ser_reg_in(fsm.dmi'length - 1 downto 0) <= fsm.dmi;

            when others =>
              fsm_next.state     <= st_idle;
              fsm_next.ser_reset <= '1';

          end case;

        else
          -- We are done sending if our serializer is done.
          -- ToDo: Wait for DMI done signal
          fsm_next.state     <= st_idle;
          fsm_next.ser_reset <= '1';
        end if;

      when st_write =>

        -- Always read when rx-fifo is not empty and serialization not done:
        if (RX_EMPTY_I = '0' and ser_done = '0') then
          fsm_next.re      <= '1';
          fsm_next.ser_run <= '1';
        else
          fsm_next.re      <= '0';
          fsm_next.ser_run <= '0';
        end if;

        if (timer_overflow = '0' and ser_done = '0') then

          case fsm.address is

            -- Address decides into which register DREC_I is serialized into.
            when ADDR_DTMCS =>
              fsm_next.ser_num_bits <= to_unsigned(fsm.dtmcs'length, 8);
              fsm_next.dtmcs        <= ser_reg_out(fsm.dtmcs'length - 1 downto 0);

            when ADDR_DMI =>
              fsm_next.ser_num_bits <= to_unsigned(fsm.dmi'length, 8);
              fsm_next.dmi          <= ser_reg_out(fsm.dmi'length - 1 downto 0);

            when others =>
              fsm_next.state     <= st_idle;
              fsm_next.ser_reset <= '1';

          end case;

        else
          -- Writing is done, if either our serializer is done or message
          -- timeout is reached.
          -- ToDo: Wait for dmi.
          fsm_next.state     <= st_idle;
          fsm_next.ser_reset <= '1';
        end if;

      when st_rw =>
        -- Read and write is performed simultaneously. Requires TX to be both
        -- ready to send, RX-Fifo to be not empty and serialization to be not
        -- done.
        if (TX_READY_I = '1' and RX_EMPTY_I = '0' and ser_done = '0') then
          fsm_next.we      <= '1';
          fsm_next.re      <= '1';
          fsm_next.ser_run <= '1';
        else
          fsm_next.we      <= '0';
          fsm_next.re      <= '0';
          fsm_next.ser_run <= '0';
        end if;

        if (timer_overflow = '0' and ser_done = '0') then

          case fsm.address is

            when ADDR_IDCODE =>
              -- IDCODE is read-only.
              fsm_next.ser_reg_in(fsm.ser_reg_in'length - 1 downto IDCODEVALUE'length) <= (others => '0');

              fsm_next.ser_num_bits                                <= to_unsigned(32, 8);
              fsm_next.ser_reg_in(IDCODEVALUE'length - 1 downto 0) <= IDCODEVALUE;

            when ADDR_DTMCS =>
              fsm_next.ser_reg_in(fsm.ser_reg_in'length - 1 downto fsm.dtmcs'length) <= (others => '0');

              fsm_next.ser_num_bits                              <= to_unsigned(fsm.dtmcs'length, 8);
              fsm_next.ser_reg_in(fsm.dtmcs'length - 1 downto 0) <= fsm.dtmcs;
              fsm_next.dtmcs                                     <= ser_reg_out(fsm.dtmcs'length - 1 downto 0);

            when ADDR_DMI =>
              fsm_next.ser_reg_in(fsm.ser_reg_in'length - 1 downto fsm.dmi'length) <= (others => '0');

              fsm_next.ser_num_bits                            <= to_unsigned(fsm.dmi'length, 8);
              fsm_next.ser_reg_in(fsm.dmi'length - 1 downto 0) <= fsm.dmi;
              fsm_next.dmi                                     <= ser_reg_out(fsm.dmi'length - 1 downto 0);

            when others =>
              fsm_next.state <= st_idle;

          end case;

        else
          fsm_next.state     <= st_idle;
          fsm_next.ser_reset <= '1';
        end if;

      when st_reset =>
        fsm_next.state   <= st_idle;
        fsm_next.re      <= '0';
        fsm_next.we      <= '0';
        fsm_next.address <= ADDR_IDCODE;
        -- ToDo: correct dtmcs clear value
        fsm_next.dtmcs <= (others => '0');
        fsm_next.dmi   <= (others => '0');
        -- Trigger reset for DMI module and de-/serializer.
        fsm_next.dmi_reset <= '1';
        -- Stop serialization.
        fsm_next.ser_reset <= '1';
        fsm_next.ser_run   <= '0';

    end case;

  end process FSM_COMB;

end architecture BEHAVIORAL;
