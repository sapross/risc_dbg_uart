----------------------------------------------------------------------------------

library IEEE;
  use IEEE.STD_LOGIC_1164.ALL;

package baudpack is

  function bddiv (hz: integer; baudrate:integer) return integer;

  function ovsamp (hz: integer) return integer;

end package baudpack;

package body baudpack is

  function bddiv (hz: integer; baudrate:integer) return integer is

    variable divider : integer := 1;

  begin

    -- Goal: 16 Samples per symbol
    if (hz > 16 * baudrate) then
      divider := hz / (16 * baudrate);
      report "Uart divider for " &
             integer'image(hz) & "HZ, " &
             integer'image(baudrate) & " Baud: " &
             integer'image(divider);
    else
      assert false
        report "Invalid frequency for baudrate generate"
        severity failure;
    end if;

    return divider;

  end function;

  function ovsamp (hz: integer) return integer is


  begin


    -- if (hz*1000000 >= 50) then
    --   report "Oversampling 16";
    --   return 16;
    -- elsif (hz*1000000 = 40) then
    --   report "Oversampling 40 HZ: 16";
    --   return 16;
    -- elsif (hz*1000000 = 30) then
    --   report "Oversampling 30 HZ: 16";
    --   return 16;
    -- elsif (hz*1000000 = 25) then
    --   report "Oversampling 25 HZ: 18";
    --   return 18;
    -- elsif (hz*1000000 = 20) then
    --   report "Oversampling 20 HZ: 16";
    --   return 16;
    -- elsif (hz*1000000 = 16) then
    --   report "Oversampling 16 HZ: 34";
    --   return 34;
    -- elsif (hz*1000000 = 12) then
    --   report "Oversampling 12 HZ: 26";
    --   return 26;
    -- elsif (hz*1000000 = 8) then
    --   report "Oversampling 8 HZ: 34";
    --   return 34;
    -- else
    --   assert false
    --     report "Invalid frequency for baudrate generate"
    --     severity failure;
    --   return 1;
    -- end if;
    return 16;
  end function;

end package body baudpack;
