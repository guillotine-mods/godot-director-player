on exitFrame
  global effectspath, whichsnd
  if not soundBusy(2) or (whichsnd <> "night1") then
    sound playFile 2, effectspath & "night1.aif"
    whichsnd = "night1"
  end if
end
