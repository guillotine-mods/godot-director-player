on exitFrame
  global effectspath
  if not soundBusy(1) then
    sound playFile 1, effectspath & "dive1.aif"
  end if
end
