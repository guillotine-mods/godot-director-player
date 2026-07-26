on exitFrame
  global effectspath, whichsnd
  if not soundBusy(2) or (whichsnd <> "sea2") then
    sound playFile 2, effectspath & "sea2.aif"
    whichsnd = "sea2"
  end if
end
