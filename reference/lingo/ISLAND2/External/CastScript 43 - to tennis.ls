on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie
  if whereami = label("exitforest2") then
    ifmovie = "1,tennisdown"
    newsyz = 5
    y = 400
    x = 300
    y2 = 257
    x2 = 270
  end if
  egozv = y
  egozh = x
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "tennis" into item 1 of nextroomdata
  walkonby()
end
