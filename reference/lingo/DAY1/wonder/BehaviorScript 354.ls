on exitFrame
  global effectspath, whichsnd
  if not soundBusy(2) or (whichsnd <> "edgewlk") then
    sound playFile 2, effectspath & "edgewlk.aif"
    whichsnd = "edgewlk"
  end if
end
