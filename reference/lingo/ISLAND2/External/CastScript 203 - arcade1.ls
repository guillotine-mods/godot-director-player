on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie
  if whereami = label("arcade") then
    ifmovie = "1,goarcade1"
    newsyz = 5
    y = 258
    x = 250
    y2 = 258
    x2 = 250
  end if
  egozv = y
  egozh = x
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "arcade" into item 1 of nextroomdata
  walkonby()
end
