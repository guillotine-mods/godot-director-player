on exitFrame
  global effectspath, whichsnd
  if not soundBusy(2) or (whichsnd <> "dive1") then
    set the volume of sound 2 to 90
    if not soundBusy(1) then
      sound playFile 2, effectspath & "dive1.aif"
    end if
    whichsnd = "dive1"
  end if
end
