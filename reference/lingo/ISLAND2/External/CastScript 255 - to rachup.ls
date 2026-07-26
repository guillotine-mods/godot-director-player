on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie
  if whereami = label("rachdown") then
    ifmovie = "1,movingup"
    newsyz = 5
    y = 328
    x = 94
    y2 = 308
    x2 = 238
  else
    if whereami = label("mountain") then
      ifmovie = "1,rachupup"
      newsyz = 5
      y = 301
      x = 42
      y2 = 308
      x2 = 238
    end if
  end if
  egozv = y
  egozh = x
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "rachup" into item 1 of nextroomdata
  walkonby()
end
