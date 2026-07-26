on exitFrame
  global effectspath, whichsnd
  if not soundBusy(2) or (whichsnd <> "monks") then
    sound playFile 2, effectspath & "monks.aif"
    whichsnd = "monks"
  end if
end
