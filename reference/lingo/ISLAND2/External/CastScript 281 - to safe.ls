on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie
  if whereami = label("hall1") then
    ifmovie = "1,tosafe"
    y = 255
    x = 472
    y2 = 308
    x2 = 238
  end if
  egozv = y
  egozh = x
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "safe" into item 1 of nextroomdata
  walkonby2()
end
