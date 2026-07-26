on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie
  if whereami = label("stairs") then
    ifmovie = "1,stairsclimbup"
    newsyz = 5
    y = 425
    x = 161
    y2 = 237
    x2 = 293
  end if
  egozv = y
  egozh = x
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "lighttop" into item 1 of nextroomdata
  walkonby()
end
