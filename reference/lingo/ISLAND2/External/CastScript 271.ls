on mouseUp
  global map, wreck
  x = map
  map = "wreck"
  go("travel" & x)
  if (item 7 of wreck = "found") or (item 7 of wreck = "stick") then
    sprite(9).visible = 1
  else
    sprite(9).visible = 0
  end if
end
