on mouseUp
  global egozh, egozv, nextroomdata, whatodo, soundspath
  nextroomdata = "000"
  if (egozv <> 298) and (egozh <> 218) then
    egozv = 298
    egozh = 218
    walkonby()
  else
    if whatodo = "stand" then
      sprite(the clickOn).visible = 0
      updateStage()
      x = "continue"
      repeat with i = 1 to the number of lines in field "objectsfield" of castLib "master"
        if (line i of field "objectsfield" of castLib "master" = "empty") and (x = "continue") then
          put "shovel" into line i of field "objectsfield" of castLib "master"
          x = "stop"
        end if
      end repeat
      sound playFile 1, soundspath & "pfshovel.aif"
      put "done" into item 3 of line 1 of field "Dprocess" of castLib "master"
      x = value(the text of field "points" of castLib "master")
      x = x + 1
      if x < 10 then
        put "00" & x into field "points" of castLib "master"
      else
        put "0" & x into field "points" of castLib "master"
      end if
      displayobject()
    end if
  end if
end
