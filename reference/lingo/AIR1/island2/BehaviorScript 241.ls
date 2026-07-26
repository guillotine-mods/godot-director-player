on exitFrame
  global soundspath
  sprite(18).visible = 1
  x = "continue"
  repeat with i = 1 to the number of lines in field "objectsfield" of castLib "master"
    if (line i of field "objectsfield" of castLib "master" = "empty") and (x = "continue") then
      put "igkey" into line i of field "objectsfield" of castLib "master"
      x = "stop"
    end if
  end repeat
  sound playFile 1, soundspath & "pfigkey.aif"
  put "done" into item 1 of line 1 of field "Dprocess" of castLib "master"
  x = value(the text of field "points" of castLib "master")
  x = x + 1
  if x < 10 then
    put "00" & x into field "points" of castLib "master"
  else
    put "0" & x into field "points" of castLib "master"
  end if
  displayobject()
  sprite(30).visible = 1
  go("mountain")
end
