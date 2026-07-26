on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie
  if whereami = label("openair1") then
    ifmovie = "1,inhall2"
    y = 238
    x = 236
    y2 = 122
    x2 = 332
  end if
  egozv = y
  egozh = x
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "hall2" into item 1 of nextroomdata
  walkonby3()
end
