on exitFrame
  global optcounter
  optcounter = optcounter + 1
  if optcounter >= 3 then
    go("choose1abc")
  else
    go("choose1")
  end if
end
