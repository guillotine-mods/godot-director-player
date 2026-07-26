on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie
  if whereami = label("openair2") then
    ifmovie = "0,0"
    y = 410
    x = 514
    y2 = 254
    x2 = 35
  end if
  sprite(35).visible = 1
  sprite(36).visible = 1
  sprite(33).visible = 1
  sprite(34).visible = 1
  egozv = y
  egozh = x
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "openair1" into item 1 of nextroomdata
  walkonby3()
end
