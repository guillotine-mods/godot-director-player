on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie
  if whereami = label("shore2") then
    ifmovie = "0,0"
    newsyz = 9
    y = 364
    x = 625
    y2 = 374
    x2 = 60
  end if
  egozv = y
  egozh = x
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "shore1" into item 1 of nextroomdata
  walkonby()
end
