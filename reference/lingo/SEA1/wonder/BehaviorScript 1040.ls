on exitFrame
  global effectspath, whichsnd
  if not soundBusy(2) or (whichsnd <> "dive1") then
    sound playFile 2, effectspath & "dive1.aif"
    whichsnd = "dive1"
  end if
end
