on exitFrame
  global effectspath, whichsnd
  if not soundBusy(2) or (whichsnd <> "figtair") then
    sound playFile 2, effectspath & "figtair.aif"
    whichsnd = "figtair"
  end if
end
