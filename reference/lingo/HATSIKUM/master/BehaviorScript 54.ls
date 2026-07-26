on exitFrame
  global optcount
  optcount = optcount + 1
  if optcount > 1 then
    go("conect1")
  else
    go("choose1")
  end if
end
