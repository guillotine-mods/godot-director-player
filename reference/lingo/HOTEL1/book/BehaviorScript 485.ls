on exitFrame
  global effectspath, whichsnd
  if item 10 of line 1 of field "Dprocess" of castLib "master" <> "done" then
  end if
  if not soundBusy(2) or (whichsnd <> "liber") then
    sound playFile 2, effectspath & "liber.aif"
    whichsnd = "liber"
  end if
end
