on exitFrame
  global effectspath
  if not soundBusy(2) then
    sound playFile 2, effectspath & "sea.aif"
  end if
end
