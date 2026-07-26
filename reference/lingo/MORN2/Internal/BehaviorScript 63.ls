on exitFrame
  global optcount
  optcount = optcount + 1
  if optcount < 3 then
    go("choose1")
  else
    go("conect1")
    optcount = 0
  end if
end
