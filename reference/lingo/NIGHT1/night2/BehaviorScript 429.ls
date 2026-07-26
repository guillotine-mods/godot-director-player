on exitFrame
  global effectspath, whichsnd
  if not soundBusy(2) or (whichsnd <> "church") then
    sound playFile 2, effectspath & "church.aif"
    whichsnd = "nigclif"
  end if
end
