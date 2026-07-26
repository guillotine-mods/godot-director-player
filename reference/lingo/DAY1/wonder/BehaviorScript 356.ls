on exitFrame
  global effectspath, whichsnd
  if not soundBusy(2) or (whichsnd <> "edgjung") then
    sound playFile 2, effectspath & "edgjung.aif"
    whichsnd = "edgjung"
  end if
end
