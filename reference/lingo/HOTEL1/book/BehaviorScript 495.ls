on exitFrame
  global effectspath, whichsnd
  if not soundBusy(2) or (whichsnd <> "hotel2") then
    sound playFile 2, effectspath & "hotel2.aif"
    whichsnd = "hotel2"
  end if
end
