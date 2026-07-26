on exitFrame
  global effectspath
  if not soundBusy(1) then
    sound playFile 1, effectspath & "wreck3.aif"
  end if
end
