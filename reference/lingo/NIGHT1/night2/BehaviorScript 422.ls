on exitFrame
  global effectspath, whichsnd
  if not soundBusy(2) or (whichsnd <> "night2") then
    sound playFile 2, effectspath & "night2.aif"
    whichsnd = "night2"
  end if
end
