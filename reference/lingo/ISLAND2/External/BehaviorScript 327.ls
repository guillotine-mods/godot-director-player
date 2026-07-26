on exitFrame
  global effectspath, whichsnd
  if not soundBusy(2) or (whichsnd <> "mind") then
    sound playFile 2, effectspath & "mind.aif"
    whichsnd = "mind"
  end if
end
