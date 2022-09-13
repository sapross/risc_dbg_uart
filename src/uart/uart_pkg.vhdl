-------------------------------------------------------------------------------
-- Title      : uart_pkg
-- Project    :
-------------------------------------------------------------------------------
-- File       : uart_pkg.vhdl
-- Author     : Stephan Proß <s.pross@stud.uni-heidelberg.de>
-- Company    :
-- Created    : 2022-09-13
-- Last update: 2022-09-13
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

  constant CMD_READ  : std_logic_vector(7 - IRLENGTH downto 0) := "001";
  constant CMD_WRITE : std_logic_vector(7 - IRLENGTH downto 0) := "010";
  constant CMD_RW    : std_logic_vector(7 - IRLENGTH downto 0) := "011";
  constant CMD_RESET : std_logic_vector(7 - IRLENGTH downto 0) := "100";

  type dmi_req_t is record
    addr : std_logic_vector(6 downto 0);
    op   : std_logic_vector(1 downto 0);
    data : std_logic_vector(31 downto 0);
  end record;

  type dmi_resp_t is record
    data : std_logic_vector(31 downto 0);
    resp : std_logic_vector(1 downto 0);
  end record;

end package uart_pkg;
