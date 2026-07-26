on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie
  if whereami = label("lighthouse") then
    ifmovie = "1,lighthousein"
    newsyz = 5
    y = 294
    x = 301
    y2 = 434
    x2 = 554
  end if
  egozv = y
  egozh = x
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "stairs" into item 1 of nextroomdata
  walkonby()
end
