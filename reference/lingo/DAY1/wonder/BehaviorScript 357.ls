on exitFrame
  global effectspath, whichsnd
  if not soundBusy(2) or (whichsnd <> "clif2") then
    sound playFile 2, effectspath & "clif2.aif"
    whichsnd = "clif2"
  end if
end
