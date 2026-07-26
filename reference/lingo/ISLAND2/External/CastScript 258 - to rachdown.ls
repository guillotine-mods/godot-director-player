on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie
  if whereami = label("rachup") then
    ifmovie = "1,movingdown"
    newsyz = 9
    y = 308
    x = 238
    y2 = 328
    x2 = 70
  end if
  egozv = y
  egozh = x
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "rachdown" into item 1 of nextroomdata
  walkonby()
end
