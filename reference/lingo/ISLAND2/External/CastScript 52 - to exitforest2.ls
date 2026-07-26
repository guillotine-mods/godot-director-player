on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie
  if whereami = label("path3") then
    ifmovie = "1,exitforest2frompath3"
    newsyz = 5
    y = 279
    x = 30
    y2 = 259
    x2 = 399
  else
    if whereami = label("forest2") then
      ifmovie = "1,exitforest2fromforest2"
      newsyz = 5
      y = 341
      x = 620
      y2 = 245
      x2 = 167
    else
      ifmovie = "1,tennisup"
      newsyz = 9
      y = 252
      x = 262
      y2 = 400
      x2 = 350
    end if
  end if
  egozv = y
  egozh = x
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "exitforest2" into item 1 of nextroomdata
  walkonby()
end
