on mouseUp
  global soundspath, dubi
  sprite(the clickOn).visible = 0
  updateStage()
  x = "continue"
  repeat with i = 1 to the number of lines in field "objectsfield" of castLib "master"
    if (line i of field "objectsfield" of castLib "master" = "empty") and (x = "continue") then
      put "pirats" into line i of field "objectsfield" of castLib "master"
      x = "stop"
    end if
  end repeat
  dubi = 3
  put "done" into item 4 of line 2 of field "Dprocess" of castLib "master"
  x = value(the text of field "points" of castLib "master")
  x = x + 1
  if x < 10 then
    put "00" & x into field "points" of castLib "master"
  else
    put "0" & x into field "points" of castLib "master"
  end if
  sound playFile 1, soundspath & "pfpirats.aif"
  displayobject()
  go(marker(1))
end
