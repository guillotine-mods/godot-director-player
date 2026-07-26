on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie
  if whereami = label("shore2") then
    ifmovie = "0,0"
    newsyz = 8
    y = 324
    x = 33
    y2 = 324
    x2 = 625
  end if
  egozv = y
  egozh = x
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "shore3" into item 1 of nextroomdata
  walkonby()
end
