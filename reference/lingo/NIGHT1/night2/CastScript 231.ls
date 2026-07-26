on mouseUp
  global soundspath
  set the visible of sprite the clickOn to 0
  x = "continue"
  repeat with i = 1 to the number of lines in field "objectsfield" of castLib "master"
    if (line i of field "objectsfield" of castLib "master" = "empty") and (x = "continue") then
      put "igkey" into line i of field "objectsfield" of castLib "master"
      x = "stop"
    end if
  end repeat
  sound playFile 1, soundspath & "pfigkey.aif"
  displayobject()
end
