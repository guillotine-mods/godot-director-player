on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie
  if whereami = label("check") then
    ifmovie = "1,forest1fromcheck"
    newsyz = 5
    y = 400
    x = 357
    y2 = 367
    x2 = 420
  else
    if whereami = label("exitforest1") then
      ifmovie = "1,forest1fromexit"
      newsyz = 4
      y = 360
      x = 620
      y2 = 364
      x2 = 257
    else
      ifmovie = "1,dwarfsup"
      newsyz = 5
      y = 206
      x = 205
      y2 = 400
      x2 = 350
    end if
  end if
  egozv = y
  egozh = x
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "forest1" into item 1 of nextroomdata
  walkonby()
end
