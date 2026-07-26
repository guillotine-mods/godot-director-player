on mouseUp
  global globalday, wreck
  if (globalday = 2) and (item 14 of wreck = "0") then
    sprite(23).visible = 1
  else
    searchfunk()
  end if
end
