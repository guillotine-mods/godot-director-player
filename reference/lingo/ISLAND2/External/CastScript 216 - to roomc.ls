on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie
  if whereami = label("rooma") then
    ifmovie = "1,toroomc"
    newsyz = 6
    y = 270
    x = 429
    y2 = 216
    x2 = 177
  else
    if whereami = label("roomb") then
      ifmovie = "1,roomcfromroomb"
      newsyz = 6
      y = 288
      x = 225
      y2 = 216
      x2 = 400
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
  put "roomc" into item 1 of nextroomdata
  walkonby()
end
