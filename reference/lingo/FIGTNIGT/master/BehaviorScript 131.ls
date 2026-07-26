on exitFrame
  global effectspath
  if not soundBusy(1) then
    sound playFile 3, effectspath & "night1.aif"
  end if
end
