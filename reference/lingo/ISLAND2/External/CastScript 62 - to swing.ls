on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie
  if whereami = label("gate") then
    sprite(6).visible = 1
    ifmovie = "1,swingup"
    newsyz = 9
    y = 287
    x = 39
    y2 = 375
    x2 = 344
  else
    if whereami = label("clif2") then
      ifmovie = "0,0"
      newsyz = 8
      y = 334
      x = 140
      y2 = 291
      x2 = 33
    end if
  end if
  egozv = y
  egozh = x
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "swing" into item 1 of nextroomdata
  walkonby()
end
