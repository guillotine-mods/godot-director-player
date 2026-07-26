on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie
  if whereami = label("veranda") then
    ifmovie = "0,0"
    newsyz = 5
    y = 232
    x = 30
    y2 = 227
    x2 = 625
  else
    if whereami = label("path2") then
      ifmovie = "0,0"
      newsyz = 7
      y = 276
      x = 600
      y2 = 290
      x2 = 30
    end if
  end if
  egozv = y
  egozh = x
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "path1" into item 1 of nextroomdata
  walkonby()
end
