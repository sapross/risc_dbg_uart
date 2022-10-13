-------------------------------------------------------------------------------
-- Title      : DMI_UART
-- Project    :
-------------------------------------------------------------------------------
-- File       : dmi_uart.vhd
-- Author     : Stephan Proß  <s.pross@stud.uni-heidelberg.de>
-- Company    :
-- Created    : 2022-09-26
-- Last update: 2022-10-13
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
    -- Signals towards TAP
    TAP_READ_I        : in    std_logic;
    TAP_WRITE_I       : in    std_logic;
    DMI_I             : in    std_logic_vector(DMI_REQ_LENGTH - 1 downto 0);
    DMI_O             : out   std_logic_vector(DMI_REQ_LENGTH - 1 downto 0);
    DONE_O            : out   std_logic;
    --- Ready/Valid Bus towards DM
    DMI_RESP_VALID_I  : in    std_logic;
    DMI_RESP_READY_O  : out   std_logic;
    DMI_RESP_I        : in    dmi_resp_t;

    DMI_REQ_VALID_O   : out   std_logic;
    DMI_REQ_READY_I   : in    std_logic;
    DMI_REQ_O         : out   dmi_req_t;

    DMI_RST_NO        : out   std_logic
  );
end entity DMI_UART;

architecture BEHAVIORAL of DMI_UART is

  type state_t is (
    st_idle,
    st_read,
    st_write,
    st_read_dmi,
    st_wait_read_dmi,
    st_write_dmi,
    st_wait_write_dmi,
    st_wait_ack
  );

  type fsm_t is record
    dmi_req  : dmi_req_t;
    dmi_resp : dmi_resp_t;

    state : state_t;
  end record fsm_t;

  signal fsm, fsm_next     : fsm_t;

  signal dmi_resp_ready    : std_logic;
  signal dmi_req_valid     : std_logic;
  signal done              : std_logic;
  signal dmi_error         : std_logic_vector(1 downto 0);
  signal tap_dmi_req       : dmi_req_t;

begin  -- architecture BEHAVIORAL

  -- Convert DMI_I into a nicer format.
  tap_dmi_req <= dmi_req_to_stl(DMI_I);

  -- Connect FSM variables to outgoing signals
  DMI_REQ_O       <= fsm.dmi_req;


  DONE_O           <= done;
  DMI_REQ_VALID_O  <= dmi_req_valid;
  DMI_RESP_READY_O <= dmi_resp_ready;

  -- Output towards tap consists of request address, response data and dmi_error.
  DMI_O(DMI_O'Length - 1 downto DMI_RESP_LENGTH ) <= fsm.dmi_req.addr;
  DMI_O(DMI_RESP_LENGTH - 1 downto 2)             <= fsm.dmi_resp.data;
  DMI_O(1 downto 0)                               <= dmi_error;

  -- Since TAP accesses DMI synchronously and does not proceed until the
  -- operation is finished, the only occurable error, DMIBUSY,
  dmi_error <= DMINOERROR;

  FSM_CORE : process (CLK) is
  begin

    if (rising_edge(CLK)) then
      if (RST = '1') then
        fsm.state               <= st_idle;
        fsm.dmi_req.addr        <= (others => '0');
        fsm.dmi_req.data        <= (others => '0');
        fsm.dmi_req.op          <= (others => '0');
        fsm.dmi_resp.resp       <= (others => '0');
        fsm.dmi_resp.data       <= (others => '0');
      else
        fsm <= fsm_next;
      end if;
    end if;

  end process FSM_CORE;

  FSM_COMB : process (RST, fsm, TAP_READ_I, TAP_WRITE_I, DMI_I, DMI_RESP_VALID_I, DMI_RESP_I, DMI_REQ_READY_I)
    is
  begin

    if (RST = '1') then
      fsm_next.state <= st_idle;
      dmi_resp_ready <= '0';
      dmi_req_valid  <= '0';
    else
      -- Default keeps all variables assoc. with fsm the same.
      fsm_next <= fsm;
      dmi_resp_ready <= '0';
      dmi_req_valid  <= '0';
      done <= '0';

      case fsm.state is

        when st_idle =>
          -- Idle state.
          -- Wait for requests from TAP
          if (TAP_READ_I = '1' and TAP_WRITE_I = '0') then
            fsm_next.state <= st_read;
          elsif (TAP_READ_I = '0' and TAP_WRITE_I = '1') then
            fsm_next.state <= st_write;
          else
            fsm_next.state <= st_idle;
          end if;

        when st_read =>
          -- DMI_O is pulled to the state of the response already.
          fsm_next.state <= st_wait_ack;

        when st_write =>
          fsm_next.dmi_req <= tap_dmi_req;
          if TAP_READ_I = '1' then
            dmi_error <= DMIBUSY;
          end if;
          if (tap_dmi_req.op = DTM_READ) then
            fsm_next.state         <= st_read_dmi;
          elsif (tap_dmi_req.op = DTM_WRITE) then
            fsm_next.dmi_req_valid <= '1';
            fsm_next.state         <= st_write_dmi;
          else
            fsm_next.state <= st_wait_ack;
          end if;

        when st_read_dmi =>
          dmi_req_valid <= '1';
          if (DMI_REQ_READY_I = '1') then
            fsm_next.state <= st_wait_read_dmi;
          end if;

        when st_wait_read_dmi =>
          -- Wait until dmi from DM is valid.
          if (DMI_RESP_VALID_I = '1') then
            -- Move into wait_ack state.
            fsm_next.dmi_resp <= DMI_RESP_I;
            fsm_next.state <= st_wait_ack;
          end if;

        when st_write_dmi =>
          dmi_req_valid <= '1';
          if (DMI_REQ_READY_I = '1') then
            fsm_next.state <= st_wait_write_dmi;
          end if;

        when st_wait_write_dmi =>
          -- Wait until dmi from DM is valid.
          if (DMI_RESP_VALID_I = '1') then
            -- Move into wait_ack state.
            fsm_next.state <= st_wait_ack;
          end if;

        when st_wait_ack =>
            done <= '1';
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
