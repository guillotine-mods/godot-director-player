on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie, sodom
  if whereami = label("recept") then
    ifmovie = "1,lobyfromrecept"
    newsyz = 6
    y = 336
    x = 55
    y2 = 251
    x2 = 490
  else
    if whereami = label("path5") then
      sodom = "booo"
      ifmovie = "2,lobyfrompath5,hotel1.dxr"
      newsyz = 5
      y = 193
      x = 589
      y2 = 206
      x2 = 330
    end if
  end if
  egozv = y
  egozh = x
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "loby" into item 1 of nextroomdata
  walkonby()
end
