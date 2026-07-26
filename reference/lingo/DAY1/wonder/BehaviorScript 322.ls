on exitFrame
  global effectspath, whichsnd
  if the locV of sprite 30 > 279 then
    sprite(34).visible = 0
  else
    sprite(34).visible = 1
  end if
  if not soundBusy(2) or (whichsnd <> "field") then
    sound playFile 2, effectspath & "field.aif"
    whichsnd = "field"
  end if
end
