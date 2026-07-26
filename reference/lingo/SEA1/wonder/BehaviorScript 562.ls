on enterFrame
  global wreck
  if item 1 of wreck = "found" then
    sprite(15).visible = 0
  else
    sprite(15).visible = 1
  end if
  set the cursor of sprite 6 to [1, 1]
  set the cursor of sprite 32 to [1, 1]
  set the cursor of sprite 34 to [1, 1]
  set the volume of sound 2 to 130
end
