on exitFrame
  if item 2 of line 3 of field "Dprocess" <> "done" then
    x = "continue"
    repeat with i = 1 to the number of lines in field "objectsfield" of castLib "master"
      if (line i of field "objectsfield" of castLib "master" = "empty") and (x = "continue") then
        put "joystk" into line i of field "objectsfield" of castLib "master"
        x = "stop"
      end if
    end repeat
    put "done" into item 2 of line 3 of field "Dprocess" of castLib "master"
    x = value(the text of field "points" of castLib "master")
    x = x + 1
    if x < 10 then
      put "00" & x into field "points" of castLib "master"
    else
      put "0" & x into field "points" of castLib "master"
    end if
  end if
end
