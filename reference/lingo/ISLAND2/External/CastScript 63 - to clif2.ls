on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie
  if whereami = label("swing") then
    ifmovie = "0,0"
    newsyz = 8
    y = 328
    x = 30
    y2 = 373
    x2 = 44
  end if
  egozv = y
  egozh = x
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "clif2" into item 1 of nextroomdata
  walkonby()
end
