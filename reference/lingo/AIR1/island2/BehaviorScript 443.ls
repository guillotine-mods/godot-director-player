on exitFrame
  global effectspath, whichsnd
  if not soundBusy(2) or (whichsnd <> "clif1") then
    sound playFile 2, effectspath & "clif1.aif"
    whichsnd = "clif1"
  end if
end
