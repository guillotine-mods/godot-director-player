on exitFrame
  global wreck
  if item 1 of wreck = "found" then
    set the visible of sprite 15 to 0
  else
    set the visible of sprite 15 to 1
  end if
end
