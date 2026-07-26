on exitFrame
  global effectspath, whichsnd, firsttalk, globalday
  x = "show"
  repeat with i = 1 to 30
    if line i of field "objectsfield" of castLib "master" = "masor" then
      x = "hide"
    end if
  end repeat
  if x = "hide" then
    sprite(17).visible = 0
  else
    sprite(17).visible = 1
  end if
  if not soundBusy(2) or (whichsnd <> "dwarfs") then
    if item 6 of firsttalk = "0" then
      sound playFile 2, effectspath & "him" & globalday & ".aif"
      put "1" into item 6 of firsttalk
    else
      sound playFile 2, effectspath & "dwarfs.aif"
    end if
    whichsnd = "dwarfs"
  end if
end
