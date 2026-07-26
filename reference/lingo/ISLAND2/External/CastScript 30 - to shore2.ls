on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie, globalday
  if globalday = 1 then
    sprite(6).visible = 0
  else
    sprite(6).visible = 1
  end if
  if whereami = label("shore1") then
    ifmovie = "0,0"
    newsyz = 8
    y = 364
    x = 23
    y2 = 354
    x2 = 627
  else
    if whereami = label("shore3") then
      ifmovie = "0,0"
      newsyz = 8
      y = 324
      x = 620
      y2 = 364
      x2 = 40
    else
      ifmovie = "1,gatetoshore"
      newsyz = 8
      y = 300
      x = 313
      y2 = 388
      x2 = 287
    end if
  end if
  egozv = y
  egozh = x
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "shore2" into item 1 of nextroomdata
  walkonby()
end
