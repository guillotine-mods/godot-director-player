on mouseUp
  global egozh, egozv, nextroomdata, whatodo, soundspath
  nextroomdata = "000"
  if (egozv <> 298) and (egozh <> 218) then
    egozv = 298
    egozh = 218
    walkonby()
  else
    if whatodo = "stand" then
      set the visible of sprite the clickOn to 0
      x = "continue"
      repeat with i = 1 to the number of lines in field "objectsfield" of castLib "master"
        if (line i of field "objectsfield" of castLib "master" = "empty") and (x = "continue") then
          put "shovel" into line i of field "objectsfield" of castLib "master"
          x = "stop"
        end if
      end repeat
      sound playFile 1, soundspath & "pfshovel.aif"
      displayobject()
    end if
  end if
end
