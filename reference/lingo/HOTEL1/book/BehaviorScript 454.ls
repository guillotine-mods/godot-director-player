on exitFrame
  global effectspath, whichsnd
  sprite(23).visible = 0
  if not soundBusy(2) or (whichsnd <> "hotel") then
    sound playFile 2, effectspath & "hotel.aif"
    whichsnd = "hotel"
  end if
end
