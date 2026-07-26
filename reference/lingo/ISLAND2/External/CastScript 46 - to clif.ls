on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie
  if whereami = label("exitforest1") then
    ifmovie = "1,exitforest1toclif"
    newsyz = 9
    y = 289
    x = 257
    y2 = 395
    x2 = 580
  else
    if whereami = label("edge6") then
      ifmovie = "1,edge6up"
      newsyz = 9
      y = 229
      x = 333
      y2 = 390
      x2 = 200
    end if
  end if
  egozv = y
  egozh = x
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "clif" into item 1 of nextroomdata
  walkonby()
end
