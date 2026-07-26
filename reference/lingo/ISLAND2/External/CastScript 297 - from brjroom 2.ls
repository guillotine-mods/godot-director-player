on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie
  if whereami = label("brjroom") then
    ifmovie = "1,frombrjroom"
    y = 220
    x = 264
    y2 = 153
    x2 = 427
  end if
  egozv = y
  egozh = x
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "hall2" into item 1 of nextroomdata
  walkonby2()
end
