on mouseUp
  global soundspath
  x = "continue"
  repeat with i = 1 to the number of lines in field "objectsfield" of castLib "master"
    if (line i of field "objectsfield" of castLib "master" = "empty") and (x = "continue") then
      put "camera" into line i of field "objectsfield" of castLib "master"
      x = "stop"
    end if
  end repeat
  sprite(16).visible = 0
  displayobject()
  sound playFile 1, soundspath & "pfcamera.aif"
end
