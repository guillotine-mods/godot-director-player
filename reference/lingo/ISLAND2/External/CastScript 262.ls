on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie
  if whereami = label("fort") then
    ifmovie = "1,fortgame"
    newsyz = 9
    y = 392
    x = 250
    y2 = 390
    x2 = 630
  end if
  egozv = y
  egozh = x
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "inside" into item 1 of nextroomdata
  walkonby()
end
