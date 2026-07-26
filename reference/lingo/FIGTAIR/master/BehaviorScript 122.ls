on exitFrame
  global effectspath
  if not soundBusy(1) then
    sound playFile 1, effectspath & "figtair.aif"
  end if
end
