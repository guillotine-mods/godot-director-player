on exitFrame
  global effectspath, whichsnd
  x = "show"
  repeat with i = 1 to 30
    if line i of field "objectsfield" of castLib "master" = "tools" then
      x = "hide"
    end if
  end repeat
  if x = "hide" then
    sprite(17).visible = 0
  else
    sprite(17).visible = 1
  end if
  if not soundBusy(2) or (whichsnd <> "rachbal2") then
    set the volume of sound 2 to 170
    sound playFile 2, effectspath & "rachbal2.aif"
    whichsnd = "rachbal2"
  end if
end
