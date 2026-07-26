on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie
  if whereami = label("hall2") then
    ifmovie = "1,tobrjroom"
    y = 220
    x = 483
    y2 = 160
    x2 = 376
  end if
  egozv = y
  egozh = x
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "brjroom" into item 1 of nextroomdata
  walkonby2()
end
