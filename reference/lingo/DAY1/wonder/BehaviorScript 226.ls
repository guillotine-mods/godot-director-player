on exitFrame
  global effectspath, whichsnd, meetings
  sprite(17).visible = 0
  if not soundBusy(2) or (whichsnd <> "sea") then
    sound playFile 2, effectspath & "sea.aif"
    whichsnd = "sea"
  end if
  if item 1 of meetings <> "done" then
    sprite(16).visible = 0
    sprite(14).visible = 0
    sprite(34).visible = 0
  else
    sprite(16).visible = 1
    sprite(14).visible = 1
    sprite(34).visible = 1
  end if
end
