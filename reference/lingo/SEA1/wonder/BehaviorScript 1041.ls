on exitFrame
  global effectspath, whichsnd
  if not soundBusy(2) or (whichsnd <> "sunk1") then
    sound playFile 2, effectspath & "sunk1.aif"
    whichsnd = "sunk1"
  end if
end
