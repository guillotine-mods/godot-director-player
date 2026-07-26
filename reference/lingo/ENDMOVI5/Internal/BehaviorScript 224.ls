on exitFrame
  global tlkpath, optcount
  optcount = optcount + 1
  if optcount < 2 then
    sound playFile 1, tlkpath & "hez147.aif"
  else
    go("conect1abc")
  end if
end
