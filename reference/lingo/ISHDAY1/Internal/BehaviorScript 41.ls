on exitFrame
  global optcount
  optcount = optcount + 1
  if optcount > 2 then
    go("conect2")
  else
    go("choose2")
  end if
end
