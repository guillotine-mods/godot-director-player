on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie
  if whereami = label("fort") then
    ifmovie = "1,climbfort"
    newsyz = 8
    y = 371
    x = 294
    y2 = 386
    x2 = 570
  end if
  egozv = y
  egozh = x
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "inside" into item 1 of nextroomdata
  walkonby()
end
