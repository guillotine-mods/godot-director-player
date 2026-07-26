on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie
  if whereami = label("rooma") then
    ifmovie = "1,tobath"
    newsyz = 8
    y = 435
    x = 339
    y2 = 443
    x2 = 167
  else
    if whereami = label("roomb") then
      ifmovie = "1,bathfromroomb"
      newsyz = 7
      y = 300
      x = 240
      y2 = 366
      x2 = 415
    else
      ifmovie = "1,path5down"
      newsyz = 4
      y = 251
      x = 352
      y2 = 182
      x2 = 193
    end if
  end if
  egozv = y
  egozh = x
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "bath" into item 1 of nextroomdata
  walkonby()
end
