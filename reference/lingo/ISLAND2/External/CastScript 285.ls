on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie
  if whereami = label("hall2") then
    ifmovie = "1,outhall2"
    y = 128
    x = 292
    y2 = 326
    x2 = 331
  end if
  egozv = y
  egozh = x
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "openair1" into item 1 of nextroomdata
  walkonby2()
end
