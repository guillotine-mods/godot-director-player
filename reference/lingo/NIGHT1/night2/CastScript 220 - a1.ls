on mouseUp
  global egozh, egozv, nextroomdata, whatodo, soundspath
  nextroomdata = "000"
  if (egozv <> 250) and (egozh <> 318) then
    egozv = 250
    egozh = 318
    walkonby()
  else
    if whatodo = "stand" then
      set the visible of sprite the clickOn to 0
      x = "continue"
      repeat with i = 1 to the number of lines in field "objectsfield" of castLib "master"
        if (line i of field "objectsfield" of castLib "master" = "empty") and (x = "continue") then
          put "sulam" into line i of field "objectsfield" of castLib "master"
          x = "stop"
        end if
      end repeat
      sound playFile 1, soundspath & "pfsulam.aif"
      displayobject()
    end if
  end if
end
