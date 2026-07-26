on exitFrame
  global effectspath, whichsnd
  if not soundBusy(2) or (whichsnd <> "rachcome") then
    set the volume of sound 2 to 200
    sound playFile 2, effectspath & "rachcome.aif"
    whichsnd = "rachcome"
  end if
end
