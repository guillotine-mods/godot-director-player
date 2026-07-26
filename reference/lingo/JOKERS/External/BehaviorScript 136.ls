on exitFrame
  if the visible of sprite 93 = 0 then
    set the visible of sprite 93 to 1
    go("cont1")
  else
    go("return2")
  end if
end
