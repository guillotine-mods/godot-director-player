on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie
  if whereami = label("clif") then
    ifmovie = "1,edge6down"
    newsyz = 4
    y = 400
    x = 150
    y2 = 221
    x2 = 381
  else
    if whereami = label("edge5") then
      ifmovie = "1,edge5up"
      newsyz = 7
      y = 176
      x = 319
      y2 = 400
      x2 = 240
    end if
  end if
  egozv = y
  egozh = x
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "edge6" into item 1 of nextroomdata
  walkonby()
end
