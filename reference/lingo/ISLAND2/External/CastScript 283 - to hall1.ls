on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie
  if whereami = label("safe") then
    ifmovie = "1,fromsafe"
    y = 380
    x = 630
    y2 = 276
    x2 = 452
  else
    if whereami = label("hall2") then
      sprite(14).visible = 0
      ifmovie = "0,0"
      y = 380
      x = 630
      y2 = 380
      x2 = 40
    end if
  end if
  egozv = y
  egozh = x
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "hall1" into item 1 of nextroomdata
  walkonby2()
end
