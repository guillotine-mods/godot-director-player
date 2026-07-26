on exitFrame
  global effectspath, whichsnd
  if not soundBusy(2) or (whichsnd <> "tennis") then
    sound playFile 2, effectspath & "tennis.aif"
    whichsnd = "tennis"
  end if
end
