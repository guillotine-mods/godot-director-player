on exitFrame
  global dubi
  if dubi = 0 then
    go("enterwarehouse1")
  else
    if dubi = 1 then
      go("enterwarehouse2")
    else
      set the visible of sprite 26 to 0
      set the visible of sprite 25 to 0
      set the visible of sprite 31 to 0
      go("enterwarehouse3")
    end if
  end if
end
