on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie
  if whereami = label("path3") then
    ifmovie = "1,path3up"
    newsyz = 7
    y = 244
    x = 374
    y2 = 307
    x2 = 610
  else
    if whereami = label("field") then
      ifmovie = "1,path4fromfield"
      newsyz = 9
      y = 360
      x = 600
      y2 = 350
      x2 = 272
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
  put "path4" into item 1 of nextroomdata
  walkonby()
end
