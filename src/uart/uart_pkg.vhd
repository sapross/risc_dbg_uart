------------------------------------------------------
-- Title      : uart_pkg
-- Project    :
-------------------------------------------------------------------------------
-- File       : uart_pkg.vhdl
-- Author     : Stephan Proß <s.pross@stud.uni-heidelberg.de>
-- Company    :
-- Created    : 2022-09-13
-- Last update: 2022-09-14
-- Platform   :
-- Standard   : VHDL'08
-------------------------------------------------------------------------------
-- Description: Package containing definitions for communication with the Debug
-- Module written in SystemVerilog.
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

  constant DTMCS_WRITE_MASK : std_logic_vector(31 downto 0) := (
    31 downto 18 => '0',
    17 downto 16 => '1',
    15 downto 0  => '0'
);

  constant DMI_REQ_LENGTH : integer := 38;
  type dmi_req_t is record
    addr : std_logic_vector(6 downto 0);
    data : std_logic_vector(31 downto 0);
    op   : std_logic_vector(1 downto 0);
  end record;

  function stl_to_dmi_req(value : std_logic_vector) return dmi_req_t;

  type dmi_resp_t is record
    data : std_logic_vector(31 downto 0);
    resp : std_logic_vector(1 downto 0);
  end record;

  function dmi_resp_to_stl(dmi_resp : dmi_resp_t) return std_logic_vector;

end package uart_pkg;


package body uart_pkg is

  function dmi_resp_to_stl(dmi_resp : dmi_resp_t) return std_logic_vector is
  begin
    return "000000" & dmi_resp.data & dmi_resp.resp;
  end function dmi_resp_to_stl;

  function stl_to_dmi_req(value : std_logic_vector) return dmi_req_t is
  begin
    return (
      addr => value(37 downto 34),
      data => value(33 downto 2),
      op => value(1 downto 0));
  end function stl_to_dmi_req;


end package body uart_pkg;
