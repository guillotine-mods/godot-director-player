on exitFrame
  global effectspath, whichsnd
  if not soundBusy(2) or (whichsnd <> "jungtof") then
    sound playFile 2, effectspath & "jungtof.aif"
    whichsnd = "jungtof"
  end if
end
