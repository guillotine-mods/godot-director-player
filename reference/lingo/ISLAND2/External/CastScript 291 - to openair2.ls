on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie, wreck
  if whereami = label("openair1") then
    ifmovie = "0,0"
    y = 310
    x = 37
    y2 = 420
    x2 = 400
  else
    if whereami = label("openair3") then
      ifmovie = "0,0"
      y = 380
      x = 630
      y2 = 250
      x2 = 40
    end if
  end if
  if wreck <> "stick" then
    sprite(12).visible = 1
  else
    sprite(12).visible = 0
  end if
  egozv = y
  egozh = x
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "openair2" into item 1 of nextroomdata
  walkonby3()
end
