on mouseUp
  global egozh, egozv, nextroomdata, whatodo, soundspath
  nextroomdata = "000"
  if (egozv <> 242) and (egozh <> 154) then
    egozv = 242
    egozh = 154
    walkonby()
  else
    if whatodo = "stand" then
      set the visible of sprite the clickOn to 0
      x = "continue"
      repeat with i = 1 to the number of lines in field "objectsfield" of castLib "master"
        if (line i of field "objectsfield" of castLib "master" = "empty") and (x = "continue") then
          put "masor" into line i of field "objectsfield" of castLib "master"
          x = "stop"
        end if
      end repeat
      sound playFile 1, soundspath & "pfmasor.aif"
      displayobject()
    end if
  end if
end
