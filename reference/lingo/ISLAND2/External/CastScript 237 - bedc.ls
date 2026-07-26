on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie
  if whereami = label("roomc") then
    ifmovie = "1,getdownbedc"
    newsyz = 7
    y = 230
    x = 365
    y2 = 230
    x2 = 365
  end if
  egozv = y
  egozh = x
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "roomc" into item 1 of nextroomdata
  walkonby()
end
