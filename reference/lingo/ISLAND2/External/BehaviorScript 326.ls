on exitFrame
  global effectspath, whichsnd
  if not soundBusy(2) or (whichsnd <> "path") then
    sound playFile 2, effectspath & "path.aif"
    whichsnd = "path"
  end if
end
