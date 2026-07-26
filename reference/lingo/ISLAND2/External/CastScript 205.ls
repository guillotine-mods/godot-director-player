on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie
  if whereami = label("arcade") then
    ifmovie = "1,goshaf"
    newsyz = 8
    y = 368
    x = 264
    y2 = 368
    x2 = 264
  end if
  egozv = y
  egozh = x
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "arcade" into item 1 of nextroomdata
  walkonby()
end
