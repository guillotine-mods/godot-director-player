on enterFrame
  global globalnight, effectspath, whichsnd
  x = "show"
  repeat with i = 1 to 30
    if line i of field "objectsfield" of castLib "master" = "sulam" then
      x = "hide"
    end if
  end repeat
  if item 1 of globalnight <> "0" then
    x = "hide"
  end if
  if x = "hide" then
    sprite(17).visible = 0
  else
    sprite(17).visible = 1
  end if
  if not soundBusy(2) or (whichsnd <> "path") then
    sound playFile 2, effectspath & "path.aif"
    whichsnd = "path"
  end if
end
