on exitFrame
  global effectspath, whichsnd
  if not soundBusy(2) or (whichsnd <> "nigclif") then
    sound playFile 2, effectspath & "nigclif.aif"
    whichsnd = "nigclif"
  end if
end
