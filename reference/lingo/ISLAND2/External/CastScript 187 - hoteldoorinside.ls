on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie
  if whereami = label("recept") then
    ifmovie = "1,today"
    newsyz = 5
    y = 143
    x = 303
    y2 = 200
    x2 = 246
  end if
  egozv = y
  egozh = x
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "veranda" into item 1 of nextroomdata
  walkonby()
end
