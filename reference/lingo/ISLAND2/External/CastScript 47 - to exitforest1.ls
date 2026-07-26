on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie
  if whereami = label("clif") then
    ifmovie = "1,exitforest1fromclif"
    newsyz = 4
    y = 381
    x = 581
    y2 = 294
    x2 = 240
  else
  end if
  egozv = y
  egozh = x
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "exitforest1" into item 1 of nextroomdata
  walkonby()
end
