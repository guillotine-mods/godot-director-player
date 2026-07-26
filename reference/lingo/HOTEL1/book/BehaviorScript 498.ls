on exitFrame
  global effectspath, whichsnd
  if not soundBusy(2) or (whichsnd <> "hotelup") then
    sound playFile 2, effectspath & "hotelup.aif"
    whichsnd = "hotelup"
  end if
end
