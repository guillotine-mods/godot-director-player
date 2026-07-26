on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie
  if whereami = label("rachbal") then
    ifmovie = "1,rachbalin"
    newsyz = 8
    y = 288
    x = 119
    y2 = 330
    x2 = 20
  end if
  egozv = y
  egozh = x
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "rachdown" into item 1 of nextroomdata
  walkonby()
end
