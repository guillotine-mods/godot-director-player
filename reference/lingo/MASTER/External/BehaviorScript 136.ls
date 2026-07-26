on exitFrame
  global effectspath, whichsnd
  if sprite(19).visible = 1 then
    sprite(14).visible = 0
  end if
  if not soundBusy(2) or (whichsnd <> "savamus") then
    sound playFile 2, effectspath & "savamus.aif"
    whichsnd = "savamus"
  end if
end
