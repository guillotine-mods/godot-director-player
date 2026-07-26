on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie
  if whereami = label("forest1") then
    ifmovie = "1,forest1toexit"
    newsyz = 6
    y = 359
    x = 268
    y2 = 360
    x2 = 630
  end if
  egozv = y
  egozh = x
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "exitforest1" into item 1 of nextroomdata
  walkonby()
end
