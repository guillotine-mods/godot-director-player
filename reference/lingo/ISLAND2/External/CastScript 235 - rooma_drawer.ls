on mouseUp
  global wreck, globalday
  if (globalday = 3) and (item 15 of wreck = "0") then
    sprite(22).visible = 1
  else
    searchfunk()
  end if
end
