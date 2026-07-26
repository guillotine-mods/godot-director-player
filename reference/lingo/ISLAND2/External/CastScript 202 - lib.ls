on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie
  if whereami = label("hall") then
    ifmovie = "1,tolib"
    newsyz = 4
    y = 330
    x = 312
    y2 = 219
    x2 = 562
  end if
  egozv = y
  egozh = x
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "lib" into item 1 of nextroomdata
  walkonby()
end
