on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie
  if whereami = label("path2") then
    ifmovie = "0,0"
    newsyz = 9
    y = 300
    x = 20
    y2 = 390
    x2 = 450
  else
    if whereami = label("path4") then
      ifmovie = "1,path3down"
      newsyz = 5
      y = 253
      x = 620
      y2 = 254
      x2 = 393
    else
      ifmovie = "1,exitforest2topath3"
      newsyz = 5
      y = 247
      x = 364
      y2 = 276
      x2 = 30
    end if
  end if
  egozv = y
  egozh = x
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "path3" into item 1 of nextroomdata
  walkonby()
end
