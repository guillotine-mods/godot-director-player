on exitFrame
  global effectspath, whichsnd
  if not soundBusy(2) or (whichsnd <> "hotelpl") then
    sound playFile 2, effectspath & "hotelpl.aif"
    whichsnd = "hotelpl"
  end if
end
