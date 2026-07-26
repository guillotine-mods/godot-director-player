on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie
  if whereami = label("mountain") then
    ifmovie = "1,climbupfort"
    newsyz = 9
    y = 293
    x = 467
    y2 = 407
    x2 = 186
  else
    if whereami = label("plane") then
      ifmovie = "0,0"
      newsyz = 9
      y = 199
      x = 10
      y2 = 410
      x2 = 433
    else
      ifmovie = "1,outsidefort"
      newsyz = 9
      y = 410
      x = 620
      y2 = 396
      x2 = 339
    end if
  end if
  egozv = y
  egozh = x
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "fort" into item 1 of nextroomdata
  walkonby()
end
