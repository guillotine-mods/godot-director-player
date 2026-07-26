on exitFrame
  global effectspath, whichsnd
  if not soundBusy(2) or (whichsnd <> "cave") then
    sound playFile 2, effectspath & "cave.aif"
    whichsnd = "cave"
  end if
end
