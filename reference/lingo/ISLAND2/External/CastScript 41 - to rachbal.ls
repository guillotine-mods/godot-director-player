on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie
  if whereami = label("edge5") then
    ifmovie = "0,0"
    newsyz = 6
    y = 384
    x = 160
    y2 = 324
    x2 = 560
  else
    if whereami = label("edge4") then
      ifmovie = "1,edge4up"
      newsyz = 4
      y = 185
      x = 455
      y2 = 285
      x2 = 77
    else
      ifmovie = "1,exitforest3up"
      newsyz = 7
      y = 241
      x = 199
      y2 = 400
      x2 = 219
    end if
  end if
  egozv = y
  egozh = x
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "rachbal" into item 1 of nextroomdata
  walkonby()
end
