on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie, wreck
  if whereami = label("openair2") then
    ifmovie = "0,0"
    y = 295
    x = 37
    y2 = 380
    x2 = 610
  end if
  if (item 5 of wreck = "done") or (item 5 of wreck = "0") then
    sprite(35).visible = 0
    sprite(36).visible = 0
  else
    sprite(35).visible = 1
    sprite(36).visible = 1
  end if
  if (item 6 of wreck = "found") or (item 5 of wreck = "0") then
    sprite(33).visible = 0
    sprite(34).visible = 0
  else
    sprite(33).visible = 1
    sprite(34).visible = 1
  end if
  egozv = y
  egozh = x
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "openair3" into item 1 of nextroomdata
  walkonby3()
end
