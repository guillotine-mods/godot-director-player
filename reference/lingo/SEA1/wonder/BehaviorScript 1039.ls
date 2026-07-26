on exitFrame
  global effectspath
  if not soundBusy(2) then
    sound playFile 2, effectspath & "wreck3.aif"
  end if
end
