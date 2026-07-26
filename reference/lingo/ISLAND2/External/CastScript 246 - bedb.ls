on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie
  if whereami = label("roomb") then
    ifmovie = "1,getdownroomb"
    newsyz = 9
    y = 358
    x = 321
    y2 = 358
    x2 = 321
  end if
  egozv = y
  egozh = x
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "roomb" into item 1 of nextroomdata
  walkonby()
end
