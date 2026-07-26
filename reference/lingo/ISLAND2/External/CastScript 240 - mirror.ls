on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie
  if whereami = label("bath") then
    ifmovie = "1,mirror"
    newsyz = 7
    y = 386
    x = 368
    y2 = 386
    x2 = 368
  end if
  egozv = y
  egozh = x
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "bath" into item 1 of nextroomdata
  walkonby()
end
