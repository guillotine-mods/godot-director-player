on exitFrame
  global tlkpath, effectspath
  sound playFile 1, tlkpath & "hez9.aif"
  if not soundBusy(2) then
    sound playFile 2, effectspath & "sea.aif"
  end if
end
