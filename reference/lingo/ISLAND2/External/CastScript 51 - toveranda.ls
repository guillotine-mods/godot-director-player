on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie
  if whereami = label("path1") then
    ifmovie = "0,0"
    newsyz = 5
    y = 230
    x = 620
    y2 = 221
    x2 = 30
  end if
  egozv = y
  egozh = x
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "veranda" into item 1 of nextroomdata
  walkonby()
end
