on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie
  if whereami = label("rooma") then
    ifmovie = "0,0"
    newsyz = 8
    y = 308
    x = 128
    y2 = 325
    x2 = 53
  else
    if whereami = label("roomb") then
      ifmovie = "1,fromroomb"
      newsyz = 7
      y = 241
      x = 494
      y2 = 254
      x2 = 232
    else
    end if
  end if
  egozv = y
  egozh = x
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "prosdor" into item 1 of nextroomdata
  walkonby()
end
