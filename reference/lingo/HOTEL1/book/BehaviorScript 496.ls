on exitFrame
  global whichsnd, effectspath
  sound playFile 1, effectspath & "doornob.aif"
  if not soundBusy(2) or (whichsnd <> "liber") then
    sound playFile 2, effectspath & "liber.aif"
    whichsnd = "liber"
  end if
end
