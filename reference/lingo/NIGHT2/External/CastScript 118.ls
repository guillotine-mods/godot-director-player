on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie, guard
  if whereami = label("rachup") then
    ifmovie = "1,rachupdown"
    newsyz = 4
    y = 308
    x = 238
    y2 = 309
    x2 = 15
  else
    if whereami = label("fort") then
      ifmovie = "1,climbdownfort"
      newsyz = 4
      y = 404
      x = 188
      y2 = 288
      x2 = 498
    end if
  end if
  egozv = y
  egozh = x
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "mountain" into item 1 of nextroomdata
  walkonby()
end
