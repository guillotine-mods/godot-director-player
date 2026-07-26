on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie
  if whereami = label("edge1") then
    ifmovie = "1,gatefromedge1"
    newsyz = 7
    y = 230
    x = 336
    y2 = 301
    x2 = 510
  else
    if whereami = label("veranda") then
      ifmovie = "1,gatefromveranda"
      newsyz = 9
      y = 324
      x = 610
      y2 = 356
      x2 = 317
    else
      ifmovie = "1,swingdown"
      newsyz = 6
      y = 371
      x = 326
      y2 = 225
      x2 = 39
    end if
  end if
  egozv = y
  egozh = x
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "gate" into item 1 of nextroomdata
  walkonby()
end
