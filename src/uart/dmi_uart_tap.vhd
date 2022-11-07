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
    CLK                        : in    std_logic;
    RST                        : in    std_logic;
    -- UART-Interface connections
    RE_O                       : out   std_logic;
    WE_O                       : out   std_logic;
    TX_READY_I                 : in    std_logic;
    RX_EMPTY_I                 : in    std_logic;
    DSEND_O                    : out   std_logic_vector(7 downto 0);
    DREC_I                     : in    std_logic_vector(7 downto 0);

    -- clear error state
    DMI_HARD_RESET_O           : out   std_logic;
    DMI_ERROR_I                : in    std_logic_vector(1 downto 0);

    -- Signals towards debug module interface
    DMI_READ_O                 : out   std_logic;
    DMI_WRITE_O                : out   std_logic;
    DMI_O                      : out   std_logic_vector(DMI_REQ_LENGTH - 1 downto 0);
    DMI_I                      : in    std_logic_vector(DMI_REQ_LENGTH - 1 downto 0);
    DMI_DONE_I                 : in    std_logic
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
    -- st_rw,
    st_reset
  );

  type fsm_t is record
    dmi : std_logic_vector(DMI_REQ_LENGTH - 1 downto 0);
    -- FSM Signals
    state       : state_t;
    address     : std_logic_vector(IrLength - 1 downto 0);
    cmd         : std_logic_vector(2 downto 0);
    data_length : unsigned (7 downto 0);
    -- Signals which trigger waiting for respective dmi operations.
    dmi_wait_read  : std_logic;
    dmi_wait_write : std_logic;
  end record fsm_t;

  signal dtmcs, dtmcs_next  : std_logic_vector(31 downto 0);
  -- UART-Interface signals
  signal re                 : std_logic;
  signal we                 : std_logic;
  -- DMI-Interace Signals
  constant MAX_BYTES        : integer := (DMI_REQ_LENGTH + 7) / 8;
  signal   dmi_read         : std_logic;
  signal   dmi_write        : std_logic;

  -- Signals for the De-/Serializer
  signal ser_reset          : std_logic;
  signal ser_run            : std_logic;
  signal ser_done           : std_logic;
  signal ser_num_bits       : unsigned(7 downto 0);
  signal ser_data_in        : std_logic_vector(7 downto 0);
  signal ser_reg_in         : std_logic_vector(MAX_BYTES * 8 - 1 downto 0);
  signal ser_reg_out        : std_logic_vector(MAX_BYTES * 8 - 1 downto 0);
  -- State machine and combinatorial next state.
  signal fsm,   fsm_next    : fsm_t;

  -- Time Out timer to catch unfished operations.
  -- Each UART-Frame takes 10 baud periods (1 Start + 8 Data + 1 Stop)
  -- Wait for the time of 5 UART-Frames.
  constant MSG_TIMEOUT      : integer := 5 * (10 * CLK_RATE / BAUD_RATE);
  signal   msg_timer        : integer range 0 to MSG_TIMEOUT;
  signal   timer_overflow   : std_logic;
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
                              state_i = st_read or
                              state_i = st_write)) then
      return true;
    else
      return false;
    end if;

  end function run_timer;

begin

  DMI_HARD_RESET_O <= dtmcs(17);
  DMI_READ_O       <= dmi_read;
  DMI_WRITE_O      <= dmi_write;
  DMI_O            <= fsm.dmi;

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
      RST        => ser_reset,
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

  ERROR_STATES : process (CLK) is
  begin

    if rising_edge(CLK) then
      if (RST = '1') then
        dtmcs( 11 downto 10 ) <= DMINoError;
      else
        if (fsm.address = ADDR_DMI and timer_overflow  ='1') then
          if (fsm.dmi_wait_read =  '1' or fsm.dmi_wait_write = '1') then
            dtmcs (11 downto 10) <= DMIBusy;
          end if;
        elsif (fsm.address = ADDR_DTMCS and fsm.state = st_write) then
          dtmcs( 11 downto 10  ) <= DMINoError;
        end if;
      end if;
    end if;

  end process ERROR_STATES;

  FSM_CORE : process (CLK) is
  begin

    if rising_edge(CLK) then
      if (RST = '1') then
        -- FSM Signals
        fsm.dmi <= (others => '0');

        dtmcs(31 downto 15) <= (others => '0');
        dtmcs(14 downto 12) <= "001";

        dtmcs(9 downto 4) <= std_logic_vector(to_unsigned(ABITS, 6));
        dtmcs(3 downto 0) <= std_logic_vector(to_unsigned(1, 4));

        fsm.state       <= st_idle;
        fsm.address     <= ADDR_IDCODE;
        fsm.cmd         <= CMD_NOP;
        fsm.data_length <= (others => '0');
      else
        fsm <= fsm_next;
        -- Only bits 31 downto 9 of dtmcs are writable. Discard the rest.
        dtmcs(dtmcs'length - 1 downto 12) <= dtmcs_next(dtmcs'length - 1 downto 12);
      end if;
    end if;

  end process FSM_CORE;

  FSM_COMB : process (fsm, DREC_I, RX_EMPTY_I, TX_READY_I, DMI_I, DMI_DONE_I, ser_done, timer_overflow) is
  begin

    fsm_next   <= fsm;
    dtmcs_next <= dtmcs;
    -- UART-Interface signals
    re <= '0';
    we <= '0';
    -- DMI-Interace Signals
    dmi_read  <= '0';
    dmi_write <= '0';

    ser_reset <= '1';
    ser_run   <= '0';
    -- Data for the De-/Serializer
    ser_data_in  <= (others => '0');
    ser_reg_in   <= (others => '0');
    ser_num_bits <= to_unsigned(1, 8);

    case fsm.state is

      when st_idle =>
        -- FSM Signals
        fsm_next.cmd         <= CMD_NOP;
        fsm_next.data_length <= (others => '0');

        fsm_next.dmi_wait_read  <= '0';
        fsm_next.dmi_wait_write <= '0';

        -- If dmihardreset or dmireset bits of dtmcs are high, trigger reset.
        if (dtmcs(17) = '1') then
          fsm_next.state <= st_reset;
        else
          fsm_next.state <= st_header;
        end if;

      when st_header =>
        -- If RX-Fifo is not empty, read and check received byte for HEADER.
        if (RX_EMPTY_I = '0') then
          re <= '1';
          -- Is the byte from RX fifo equal to our header?
          if (DREC_I = HEADER) then
            -- If yes, proceed to CmdAddr.
            fsm_next.state <= st_cmdaddr;
          end if;
        end if;

      when st_cmdaddr =>
        -- If RX-Fifo is not empty, read and and apply received byte to cmd and
        -- address.
        if (RX_EMPTY_I = '0') then
          re <= '1';
          -- Decode into command and address.
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
        -- If RX-Fifo is not empty, read and and apply received byte to
        -- data_length.
        if (RX_EMPTY_I = '0') then
          re <= '1';
          -- Apply byte as unsigned integer to data_length.
          fsm_next.data_length <= unsigned(DREC_I);

          -- If we access dmi register, trigger
          if (fsm.address = ADDR_DMI) then
            fsm_next.dmi_wait_read  <= '1';
            fsm_next.dmi_wait_write <= '1';
          end if;
          -- Move on to the next state determined by command.
          case fsm.cmd is

            when CMD_READ =>
              fsm_next.state <= st_read;

            when CMD_WRITE =>
              fsm_next.state <= st_write;

              -- when CMD_RW =>
              --   fsm_next.state <= st_rw;

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
        -- Serialize addressed register into bytes and send over TX.
        -- De-/Serializer is active during this state.
        ser_reset <= '0';
        -- If serialization is not done...
        -- and we do not need to wait for dmi...
        if (fsm.dmi_wait_read = '1') then
          -- If we do have to wait for dmi...
          if (DMI_DONE_I = '0' and timer_overflow = '0') then
            -- ...tell dmi_handler to read...
            fsm_next.dmi_wait_read <= '1';
            dmi_read               <= '1';
          else
            --- ...otherwise we're done.
            fsm_next.dmi_wait_read <= '0';
            dmi_read               <= '0';
            fsm_next.dmi           <= DMI_I;
          end if;
        else
          -- always write to TX if ready.
          we      <= TX_READY_I and not ser_done;
          ser_run <= TX_READY_I;
          if (ser_done = '1') then
            -- We are done sending if our serializer is done.
            fsm_next.state <= st_idle;
          end if;
        end if;

        case fsm.address is

          -- Dependent on address, load up the serializers register input
          -- with the appropriate data.
          when ADDR_IDCODE =>
            ser_reg_in(ser_reg_in'length - 1 downto IDCODEVALUE'length) <= (others => '0');
            ser_reg_in(IDCODEVALUE'length - 1 downto 0)                 <= IDCODEVALUE;
            -- IDCODE Register has 32 bits.
            ser_num_bits <= to_unsigned(32, 8);

          when ADDR_DTMCS =>
            ser_reg_in(ser_reg_in'length - 1 downto dtmcs'length) <= (others => '0');
            ser_reg_in(dtmcs'length - 1 downto 0)                 <= dtmcs;

            ser_num_bits <= to_unsigned(dtmcs'length, 8);

          when ADDR_DMI =>
            -- Read to dmi returns less bits than required to write since
            -- dmi_req'length > dmi_resp'length
            ser_reg_in(ser_reg_in'length - 1 downto DMI_RESP_LENGTH) <= (others => '0');
            ser_reg_in(DMI_RESP_LENGTH - 1 downto 0)                 <= fsm.dmi(DMI_RESP_LENGTH - 1 downto 0);

            ser_num_bits <= to_unsigned(fsm.dmi'length, 8);

          when others =>
            fsm_next.state <= st_idle;

        end case;

      when st_write =>
        -- Deserialze bytes received over RX into addressed register.
        -- De-/Serializer is active during this state.
        ser_reset <= '0';
        -- If deserialzation is not done and timeout timer has not run out ...
        if (timer_overflow = '0') then
          if (ser_done = '0') then
            -- ...always read when rx-fifo is not empty:
            if (RX_EMPTY_I = '0') then
              re      <= '1';
              ser_run <= '1';
            else
              re      <= '0';
              ser_run <= '0';
            end if;
          else
            -- Deserializing is done.
            -- Do we need to write to dmi?
            if (fsm.dmi_wait_write = '1') then
              -- Is the dmi_handler done?
              if (DMI_DONE_I = '0') then
                fsm_next.dmi_wait_write <= '1';
                dmi_write               <= '1';
              else
                fsm_next.dmi_wait_write <= '0';
                dmi_write               <= '0';
              end if;
            else
              -- Either dmi write is done or we didn't need to wait for the
              -- handler anyway.
              fsm_next.state <= st_idle;
            end if;
          end if;
        else
          -- Message timeout is reached.
          fsm_next.state <= st_idle;
        end if;

        case fsm.address is

          -- Address decides into which register DREC_I is serialized into.
          when ADDR_DTMCS =>
            ser_num_bits <= to_unsigned(dtmcs'length, 8);

            if (ser_done = '1') then
              dtmcs_next <= ser_reg_out(dtmcs'length - 1 downto 0);
            end if;

          when ADDR_DMI =>
            ser_num_bits <= to_unsigned(fsm.dmi'length, 8);

            if (ser_done = '1') then
              fsm_next.dmi <= ser_reg_out(fsm.dmi'length - 1 downto 0);
            end if;

          when others =>
            fsm_next.state <= st_idle;
            ser_reset      <= '1';

        end case;

        -- when st_rw =>
        --   -- Deserialze bytes received over RX into addressed register and send
        --   -- addressed register seralized over TX.
        --   -- De-/Serializer is active during this state.
        --   ser_reset <= '0';
        --   -- Read and write is performed simultaneously. Requires TX to be both
        --   -- ready to send, RX-Fifo to be not empty and serialization to be not
        --   -- done.
        --   if (timer_overflow = '0') then
        --     -- Do we need to read from the dmi?
        --     if (fsm.dmi_wait_read = '1') then
        --       -- If we do have to wait for dmi...
        --       if (DMI_DONE_I = '0') then
        --         -- ...tell dmi_handler to read...
        --         fsm_next.dmi_wait_read <= '1';
        --         dmi_read               <= '1';
        --       else
        --         --- ...otherwise we're done.
        --         fsm_next.dmi_wait_read <= '0';
        --         dmi_read               <= '0';
        --         fsm_next.dmi           <= DMI_I;
        --       end if;
        --     else
        --       if (TX_READY_I = '1' and RX_EMPTY_I = '0') then
        --         we      <= '1';
        --         re      <= '1';
        --         ser_run <= '1';
        --       else
        --         we      <= '0';
        --         re      <= '0';
        --         ser_run <= '0';
        --       end if;
        --     end if;
        --     if (ser_done = '1') then
        --       -- deserializing is done.
        --       -- Do we need to write to dmi?
        --       if (fsm.dmi_wait_write = '1') then
        --         -- Is the dmi_handler done?
        --         if (DMI_DONE_I = '0') then
        --           fsm_next.dmi_wait_write <= '1';
        --           dmi_write               <= '1';
        --         else
        --           fsm_next.dmi_wait_write <= '0';
        --           dmi_write               <= '0';
        --         end if;
        --       else
        --         -- Either dmi write is done or we didn't need to wait for the
        --         -- handler anyway.
        --         fsm_next.state <= st_idle;
        --       end if;
        --     end if;
        --   else
        --     -- Message timeout.
        --     fsm_next.state <= st_idle;
        --   end if;

        --   case fsm.address is

        --     when ADDR_IDCODE =>
        --       -- IDCODE is read-only.
        --       ser_reg_in(ser_reg_in'length - 1 downto IDCODEVALUE'length) <= (others => '0');

        --       ser_num_bits                                <= to_unsigned(32, 8);
        --       ser_reg_in(IDCODEVALUE'length - 1 downto 0) <= IDCODEVALUE;

        --     when ADDR_DTMCS =>
        --       ser_reg_in(ser_reg_in'length - 1 downto dtmcs'length) <= (others => '0');

        --       ser_num_bits                              <= to_unsigned(dtmcs'length, 8);
        --       ser_reg_in(dtmcs'length - 1 downto 0) <= dtmcs;
        --       dtmcs_next                            <= ser_reg_out(dtmcs'length - 1 downto 0);

        --     when ADDR_DMI =>
        --       ser_reg_in(ser_reg_in'length - 1 downto fsm.dmi'length) <= (others => '0');

        --       ser_num_bits                            <= to_unsigned(fsm.dmi'length, 8);
        --       ser_reg_in(fsm.dmi'length - 1 downto 0) <= fsm.dmi;
        --       fsm_next.dmi                            <= ser_reg_out(fsm.dmi'length - 1 downto 0);

        --     when others =>
        --       fsm_next.state <= st_idle;

        --   end case;

      when st_reset =>
        -- Reset state as the result of a reset command from host system.
        fsm_next.state   <= st_idle;
        fsm_next.address <= ADDR_IDCODE;
        dtmcs_next       <= (others => '0');
        fsm_next.dmi     <= (others => '0');
        -- Stop serialization.
        ser_reset <= '1';
        ser_run   <= '0';

    end case;

  end process FSM_COMB;

end architecture BEHAVIORAL;
