on exitFrame
  global effectspath, whichsnd
  if not soundBusy(2) or (whichsnd <> "field") then
    sound playFile 2, effectspath & "field.aif"
    whichsnd = "field"
  end if
end
