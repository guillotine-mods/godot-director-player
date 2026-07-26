on exitFrame
  global effectspath, whichsnd
  if not soundBusy(2) or (whichsnd <> "lgtin") then
    sound playFile 2, effectspath & "lgtin.aif"
    whichsnd = "lgtin"
  end if
end
