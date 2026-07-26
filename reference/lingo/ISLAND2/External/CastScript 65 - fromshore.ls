on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie
  if whereami = label("shore2") then
    ifmovie = "1,shore2up"
    newsyz = 7
    y = 390
    x = 297
    y2 = 314
    x2 = 300
  end if
  egozv = y
  egozh = x
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "gate" into item 1 of nextroomdata
  walkonby()
end
