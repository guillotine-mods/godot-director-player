on mouseUp
  global wreck, soundspath
  sprite(the clickOn).visible = 0
  updateStage()
  put "found" into item 3 of wreck
  x = "continue"
  repeat with i = 1 to the number of lines in field "objectsfield" of castLib "master"
    if (line i of field "objectsfield" of castLib "master" = "empty") and (x = "continue") then
      put "prplor" into line i of field "objectsfield" of castLib "master"
      x = "stop"
    end if
  end repeat
  put "done" into item 7 of line 2 of field "Dprocess" of castLib "master"
  x = value(the text of field "points" of castLib "master")
  x = x + 1
  if x < 10 then
    put "00" & x into field "points" of castLib "master"
  else
    put "0" & x into field "points" of castLib "master"
  end if
  displayobject()
  sound playFile 1, soundspath & "pfprplor.aif"
end
