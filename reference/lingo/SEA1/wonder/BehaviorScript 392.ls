on enterFrame
  global dubi, ifmovie, nextroomdata, wreck
  if dubi < 2 then
    sprite(14).visible = 1
  else
    sprite(14).visible = 0
  end if
  if item 4 of wreck = "done" then
    sprite(22).visible = 1
    sprite(23).visible = 1
    sprite(24).visible = 1
    sprite(29).visible = 0
  else
    sprite(22).visible = 0
    sprite(23).visible = 0
    sprite(24).visible = 0
    sprite(29).visible = 1
  end if
end
