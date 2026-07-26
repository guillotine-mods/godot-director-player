on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie
  if whereami = label("rachdown") then
    ifmovie = "1,rachbalout"
    newsyz = 5
    y = 328
    x = 20
    y2 = 289
    x2 = 77
  end if
  egozv = y
  egozh = x
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "rachbal" into item 1 of nextroomdata
  walkonby()
end
