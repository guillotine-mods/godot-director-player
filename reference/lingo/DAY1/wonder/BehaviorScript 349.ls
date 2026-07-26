on exitFrame
  global effectspath, whichsnd
  if not soundBusy(2) or (whichsnd <> "sea") then
    sound playFile 2, effectspath & "sea.aif"
    whichsnd = "sea"
  end if
end
