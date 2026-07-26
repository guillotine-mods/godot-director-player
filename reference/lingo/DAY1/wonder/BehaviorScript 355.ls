on exitFrame
  global effectspath, whichsnd
  if not soundBusy(2) or (whichsnd <> "rachfar") then
    sound playFile 2, effectspath & "rachfar.aif"
    whichsnd = "rachfar"
  end if
end
