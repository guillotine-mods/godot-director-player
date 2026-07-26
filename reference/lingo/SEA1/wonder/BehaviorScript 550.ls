on mouseUp
  global egozh, egozv, nextroomdata, whatodo, wreck, soundspath, dubi
  nextroomdata = "000"
  if (egozv <> 290) and (egozh <> 390) then
    egozv = 290
    egozh = 390
    walkonby2()
  else
    if whatodo = "stand" then
      sprite(the clickOn).visible = 0
      updateStage()
      put "found" into item 1 of wreck
      x = "continue"
      repeat with i = 1 to the number of lines in field "objectsfield" of castLib "master"
        if (line i of field "objectsfield" of castLib "master" = "empty") and (x = "continue") then
          put "edna" into line i of field "objectsfield" of castLib "master"
          x = "stop"
        end if
      end repeat
      x = value(the text of field "points" of castLib "master")
      x = x + 1
      if x < 10 then
        put "00" & x into field "points" of castLib "master"
      else
        put "0" & x into field "points" of castLib "master"
      end if
      sound playFile 1, soundspath & "pfedna.aif"
      displayobject()
    end if
  end if
end
