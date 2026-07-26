on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie
  if whereami = label("path1") then
    ifmovie = "0,0"
    newsyz = 8
    y = 286
    x = 30
    y2 = 290
    x2 = 610
  else
    if whereami = label("path3") then
      ifmovie = "0,0"
      newsyz = 9
      y = 380
      x = 600
      y2 = 348
      x2 = 30
    end if
  end if
  egozv = y
  egozh = x
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "path2" into item 1 of nextroomdata
  walkonby()
end
