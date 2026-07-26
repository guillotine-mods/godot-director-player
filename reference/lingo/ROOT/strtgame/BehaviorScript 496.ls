on exitFrame
  global effectspath
  if not soundBusy(2) then
    sound playFile 2, effectspath & "song1.aif"
  end if
end
