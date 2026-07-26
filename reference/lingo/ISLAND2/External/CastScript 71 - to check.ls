on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie
  if whereami = label("forest1") then
    ifmovie = "1,forest1tocheck"
    newsyz = 9
    y = 366
    x = 399
    y2 = 400
    x2 = 357
  end if
  egozv = y
  egozh = x
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "check" into item 1 of nextroomdata
  walkonby()
end
