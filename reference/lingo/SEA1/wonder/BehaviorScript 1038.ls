on exitFrame
  global effectspath, whichsnd
  if not soundBusy(2) then
    sound playFile 2, effectspath & "wreck2.aif"
  end if
end
