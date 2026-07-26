on exitFrame
  global effectspath, whichsnd
  if not soundBusy(2) or (whichsnd <> "rachbal") then
    sound playFile 2, effectspath & "rachbal.aif"
    whichsnd = "rachbal"
  end if
end
