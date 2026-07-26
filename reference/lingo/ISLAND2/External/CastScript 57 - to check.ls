on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie
  if whereami = label("path5") then
    ifmovie = "1,checkdown"
    newsyz = 5
    y = 208
    x = 27
    y2 = 236
    x2 = 520
  else
  end if
  egozv = y
  egozh = x
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "check" into item 1 of nextroomdata
  walkonby()
end
