on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie
  if whereami = label("rachbal") then
    ifmovie = "0,0"
    newsyz = 9
    y = 313
    x = 578
    y2 = 395
    x2 = 100
  else
    if whereami = label("edge6") then
      ifmovie = "1,edge5down"
      newsyz = 4
      y = 396
      x = 186
      y2 = 175
      x2 = 289
    end if
  end if
  egozv = y
  egozh = x
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "edge5" into item 1 of nextroomdata
  walkonby()
end
