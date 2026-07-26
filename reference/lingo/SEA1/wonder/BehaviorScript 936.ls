on exitFrame
  global wreck
  if item 8 of wreck contains "found" then
    sprite(4).visible = 0
  else
    sprite(4).visible = 1
  end if
  go("entercave2")
end
