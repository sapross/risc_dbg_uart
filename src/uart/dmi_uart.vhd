-------------------------------------------------------------------------------
-- Title      : DMI_UART
-- Project    :
-------------------------------------------------------------------------------
-- File       : dmi_uart.vhd
-- Author     : Stephan Proß  <s.pross@stud.uni-heidelberg.de>
-- Company    :
-- Created    : 2022-09-26
-- Last update: 2022-10-12
-- Platform   :
-- Standard   : VHDL'93/02
-------------------------------------------------------------------------------
-- Description: Debug Module Interface for handling communication with Debug
-- Module and the TAP.
-------------------------------------------------------------------------------
-- Copyright (c) 2022
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author  Description
-- 2022-09-26  1.0      spross  Created
-------------------------------------------------------------------------------

library IEEE;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library WORK;
  use work.uart_pkg.all;

entity DMI_UART is
  port (
    CLK               : in    std_logic;
    RST               : in    std_logic;
    TESTMODE_I        : in    std_logic;
    -- Signals towards TAP
    TAP_READ_I        : in    std_logic;
    TAP_WRITE_I       : in    std_logic;
    DMI_I             : in    std_logic_vector(DMI_REQ_LENGTH - 1 downto 0);
    DMI_O             : out   std_logic_vector(DMI_REQ_LENGTH - 1 downto 0);
    DONE_O            : out   std_logic;
    --- Ready/Valid Bus towards DM
    DMI_READ_VALID_I  : in    std_logic;
    DMI_READ_READY_O  : out   std_logic;
    DMI_READ_I        : in    dmi_resp_t;

    DMI_WRITE_VALID_O : out   std_logic;
    DMI_WRITE_READY_I : in    std_logic;
    DMI_WRITE_O       : out   dmi_req_t;

    DMI_RST_NO        : out   std_logic
  );
end entity DMI_UART;

architecture BEHAVIORAL of DMI_UART is

  type state_t is (
    st_idle,
    st_wait_read_dmi,
    st_wait_write_dmi,
--    st_wait_rw_dmi,
    st_wait_ack,
    st_reset
  );

  type fsm_t is record
    dmi : std_logic_vector(DMI_REQ_LENGTH - 1 downto 0);

    dmi_read_ready  : std_logic;
    dmi_write_valid : std_logic;
    state           : state_t;
  end record fsm_t;

  signal fsm, fsm_next : fsm_t;

begin  -- architecture BEHAVIORAL

  -- Connect FSM variables to outgoing signals
  DONE_O            <= fsm.done;
  DMI_WRITE_O       <= stl_to_dmi_req(fsm.dmi);
  DMI_O             <= fsm.dmi;
  DMI_READ_READY_I  <= fsm.dmi_read_ready;
  DMI_WRITE_VALID_I <= fsm.dmi_write_valid;

  FSM_CORE : process (CLK) is
  begin

    if (rising_edge(CLK)) then
      if (RST = '1') then
        fsm.state           <= st_idle;
        fsm.dmi             <= (others => '0');
        fsm.dmi_read_ready  <= '0';
        fsm.dmi_write_valid <= '0';
      else
        fsm <= fsm_next;
      end if;
    end if;

  end process FSM_CORE;

  FSM_COMB : process (RST, fsm, TAP_READ_I, TAP_WRITE_I, DMI_I, DMI_READ_VALID_I, DMI_READ_I, DMI_WRITE_READY_I)
    is
  begin

    if (RST = '1') then
      fsm_next.state           <= st_idle;
      fsm_next.dmi             <= (others => '0');
      fsm_next.dmi_read_ready  <= '0';
      fsm_next.dmi_write_valid <= '0';
    else
      -- Default keeps all variables assoc. with fsm the same.
      fsm_next <= fsm;

      case fsm.state is

        when st_idle =>
          -- Idle state.
          -- Wait for requests from TAP
          if (TAP_READ_I = '1' and TAP_WRITE_I = '0') then
            -- Send read request to DM
            fsm_next.dmi_read_ready <= '1';
            fsm_next.state          <= st_wait_read_dmi;
          elsif (TAP_READ_I = '0' and TAP_WRITE_I = '1') then
            -- Apply dmi from tap to register
            fsm_next.dmi <= DMI_I;
            -- Send write request to DM.
            fsm_next.dmi_write_valid <= '1';
            fsm_next.state           <= st_wait_write_dmi;
          elsif (TAP_READ_I = '1' and TAP_WRITE_I = '1') then
            -- Simultaneous reading and writing (i.e. register exchange).
            -- Apply dmi from tap to local register.
            fsm_next.dmi <= DMI_I;
            -- Signal both reading and writing intent.
            fsm_next.dmi_write_valid <= '1';
            fsm_next.dmi_read_ready  <= '1';
            fsm_next.state           <= st_wait_rw_dmi;
          else
            fsm_next.state <= st_idle;
          end if;

        when st_wait_read_dmi =>
          -- Wait until dmi from DM is valid.
          if (DMI_READ_VALID_I = '1') then
            -- Apply dmi response to dmi register.
            fsm_next.dmi <= dmi_resp_to_stl(DMI_READ_I);
            -- Release ready signal.
            fsm_next.dmi_read_ready <= '0';
            -- Mark transaction as done.
            fsm_next.done <= '1';
            -- Move into wait_ack state.
            fsm_next.state <= st_wait_ack;
          end if;

        when st_wait_write_dmi =>
          -- Wait until dmi is ready to read.
          if (DMI_WRITE_READY_I = '1') then
            -- Release valid signal.
            fsm_next.dmi_write_valid <= '0';
            -- Mark transaction as done.
            fsm_next.done <= '1';
            -- Move into wait_ack state.
            fsm_next.state <= st_wait_ack;
          end if;

        -- when st_wait_rw_dmi =>
        --   -- Wait until write and read request are both done.
        --   if (DMI_WRITE_READY_I = '1' and DMI_READ_VALID_I = '1') then
        --     -- Lower valid ready signals
        --     fsm_next.dmi_write_valid <= '0';
        --     fsm_next.dmi_read_ready  <= '0';
        --     -- Apply dmi response from tap to local regsiter.
        --     fsm_next.dmi <= dmi_resp_to_stl(DMI_READ_I);

        --     -- Signal TAP that transaction is done.
        --     fsm_next.done <= '1';
        --     -- Move into wati_ack state.
        --     fsm_next.state <= st_wait_ack;
        --   end if;

        when st_wait_ack =>
          -- Wait for acknowledgement by TAP through lowering both read and
          -- write request bits.
          if (TAP_WRITE_I = '0' and TAP_READ_I = '0') then
            fsm_next.done  <= '0';
            fsm_next.state <= st_idle;
          end if;

        when st_reset =>

        when others =>
          fsm_next.state <= st_idle;

      end case;

    end if;

  end process FSM_COMB;

end architecture BEHAVIORAL;
