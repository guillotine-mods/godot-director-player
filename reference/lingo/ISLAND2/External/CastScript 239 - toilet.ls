on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie
  if whereami = label("bath") then
    ifmovie = "1,toialet"
    newsyz = 8
    y = 401
    x = 258
    y2 = 401
    x2 = 258
  end if
  egozv = y
  egozh = x
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "bath" into item 1 of nextroomdata
  walkonby()
end
