on exitFrame
  global effectspath, whichsnd
  if not soundBusy(2) or (whichsnd <> "arcade") then
    sound playFile 2, effectspath & "arcade.aif"
    whichsnd = "arcade"
  end if
end
