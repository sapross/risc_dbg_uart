------------------------------------------------------
-- Title      : uart_pkg
-- Project    :
-------------------------------------------------------------------------------
-- File       : uart_pkg.vhdl
-- Author     : Stephan Proß <s.pross@stud.uni-heidelberg.de>
-- Company    :
-- Created    : 2022-09-13
-- Last update: 2022-09-21
-- Platform   :
-- Standard   : VHDL'08
-------------------------------------------------------------------------------
-- Description: Package containing definitions for communication with the Debug
-- Module, which is  written in SystemVerilog.
-------------------------------------------------------------------------------
-- Copyright (c) 2022
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author  Description
-- 2022-09-13  1.0      spross  Created
-------------------------------------------------------------------------------

library IEEE;
  use IEEE.STD_LOGIC_1164.ALL;
  use IEEE.NUMERIC_STD.ALL;

package uart_pkg is

  constant IRLENGTH    : integer := 5;
  constant IDCODEVALUE : std_logic_vector(31 downto 0) := X"00000001";

  constant HEADER : std_logic_vector( 7 downto 0) := X"01"; -- SOF in ASCII

  constant CMD_NOP   : std_logic_vector(7 - IRLENGTH downto 0) := "000";
  constant CMD_READ  : std_logic_vector(7 - IRLENGTH downto 0) := "001";
  constant CMD_WRITE : std_logic_vector(7 - IRLENGTH downto 0) := "010";
  constant CMD_RW    : std_logic_vector(7 - IRLENGTH downto 0) := "011";
  constant CMD_RESET : std_logic_vector(7 - IRLENGTH downto 0) := "100";

  constant DTMCS_WRITE_MASK : std_logic_vector(31 downto 0) :=
  (
    31 downto 18 => '0',
    17 downto 16 => '1',
    15 downto 0  => '0'
  );

  constant ABITS          : integer := 7;
  constant DMI_REQ_LENGTH : integer := 41;

  type dtmcs_t is record
    zero1        : std_logic_vector(31 downto 18);
    dmihardreset : std_logic_vector(17 downto 17);
    dmireset     : std_logic_vector(16 downto 16);
    zero0        : std_logic_vector(15 downto 15);
    idle         : std_logic_vector(14 downto 12);
    dmistat      : std_logic_vector(11 downto 10);
    ABITS        : std_logic_vector(9 downto 4);
    version      : std_logic_vector(3 downto 0);
  end record;

  constant DTMCS_ZERO : dtmcs_t :=
  (
    zero1 => (others => '0'),
    dmihardreset => (others => '0'),
    dmireset => (others => '0'),
    zero0 => (others => '0'),
    idle => (others => '0'),
    dmistat => (others => '0'),
    ABITS => std_logic_vector(to_unsigned(ABITS, 5)),
    version => std_logic_vector(to_unsigned(1, 3))
  );

  type dmi_req_t is record
    addr : std_logic_vector(ABITS - 1 downto 0);
    data : std_logic_vector(31 downto 0);
    op   : std_logic_vector(1 downto 0);
  end record;

  function stl_to_dmi_req (value : std_logic_vector) return dmi_req_t;

  function dmi_req_to_stl (dmi_req : dmi_req_t) return std_logic_vector;

  type dmi_resp_t is record
    data : std_logic_vector(31 downto 0);
    resp : std_logic_vector(1 downto 0);
  end record;

  function dmi_resp_to_stl (dmi_resp : dmi_resp_t) return std_logic_vector;

  function stl_to_dmi_resp (value : std_logic_vector) return dmi_resp_t;

end package uart_pkg;

package body uart_pkg is

  function dmi_resp_to_stl (dmi_resp : dmi_resp_t) return std_logic_vector is
  begin

    return "0000000" & dmi_resp.data & dmi_resp.resp;

  end function dmi_resp_to_stl;

  function stl_to_dmi_resp (value : std_logic_vector) return dmi_resp_t is
  begin

    return (
      data => value(33 downto 2),
      resp => value(1 downto 0));

  end function;

  function dmi_req_to_stl (dmi_req : dmi_req_t) return std_logic_vector is
  begin

    return dmi_req.addr & dmi_req.op & dmi_req.data;

  end function;

  function stl_to_dmi_req (value : std_logic_vector) return dmi_req_t is
  begin

    return (
      addr => value(37 downto 34),
      op => value(33 downto 32),
      data => value(31 downto 0));

  end function stl_to_dmi_req;

end package body uart_pkg;
