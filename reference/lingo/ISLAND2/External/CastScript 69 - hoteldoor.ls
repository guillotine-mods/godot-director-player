on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie, sodom
  if whereami = label("veranda") then
    sodom = "booo"
    ifmovie = "2,receptfromday,hotel1.dxr"
    newsyz = 5
    y = 162
    x = 233
    y2 = 205
    x2 = 278
  end if
  egozv = y
  egozh = x
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "recept" into item 1 of nextroomdata
  walkonby()
end
