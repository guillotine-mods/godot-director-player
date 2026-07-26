on exitFrame
  global effectspath, whichsnd
  if not soundBusy(2) or (whichsnd <> "veranda") then
    sound playFile 2, effectspath & "veranda.aif"
    whichsnd = "veranda"
  end if
end
