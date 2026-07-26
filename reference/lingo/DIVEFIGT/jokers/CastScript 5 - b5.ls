on mouseUp
  global egozh, egozv, nextroomdata, whatodo, soundspath, dubi
  nextroomdata = "000"
  if (egozv <> 390) and (egozh <> 390) then
    egozv = 390
    egozh = 390
    walkonby2()
  else
    if whatodo = "stand" then
      set the visible of sprite the clickOn to 0
      x = "continue"
      repeat with i = 1 to the number of lines in field "objectsfield" of castLib "master"
        if (line i of field "objectsfield" of castLib "master" = "empty") and (x = "continue") then
          put "glass" into line i of field "objectsfield" of castLib "master"
          x = "stop"
        end if
      end repeat
      dubi = 2
      sound playFile 1, soundspath & "pfglass.aif"
      displayobject()
    end if
  end if
end
