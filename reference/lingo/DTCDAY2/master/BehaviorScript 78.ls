on exitFrame
  global optcount
  optcount = optcount + 1
  if optcount < 3 then
    go("choose2")
  else
    go("conect2")
    optcount = 0
  end if
end
