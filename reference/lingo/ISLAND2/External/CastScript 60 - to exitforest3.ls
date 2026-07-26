on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie
  if whereami = label("dwarfs") then
    ifmovie = "0,0"
    newsyz = 8
    y = 400
    x = 330
    y2 = 388
    x2 = 270
  else
    if whereami = label("rachbal") then
      ifmovie = "1,exitforest3down"
      newsyz = 4
      y = 400
      x = 249
      y2 = 224
      x2 = 184
    end if
  end if
  egozv = y
  egozh = x
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "exitforest3" into item 1 of nextroomdata
  walkonby()
end
