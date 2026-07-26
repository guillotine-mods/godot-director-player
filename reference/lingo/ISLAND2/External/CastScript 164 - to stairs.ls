on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie
  if whereami = label("lighttop") then
    ifmovie = "1,stairsclimbdown"
    newsyz = 5
    y = 263
    x = 237
    y2 = 423
    x2 = 121
  end if
  egozv = y
  egozh = x
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "stairs" into item 1 of nextroomdata
  walkonby()
end
