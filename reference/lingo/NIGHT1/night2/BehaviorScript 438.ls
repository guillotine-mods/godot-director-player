on exitFrame
  global egozh, egozv, whatodo, whereami, newsyz, ifmovie, nextroomdata
  if whereami = label("fort") then
    ifmovie = "0,0"
    newsyz = 8
    y = 371
    x = 294
    y2 = 371
    x2 = 294
  end if
  egozv = y
  egozh = x
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "fort" into item 1 of nextroomdata
  go(item 1 of nextroomdata)
  sprite(30).visible = 1
  nextroomdata = "000"
end
