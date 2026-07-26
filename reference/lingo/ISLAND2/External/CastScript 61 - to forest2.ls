on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie
  if whereami = label("dwarfs") then
    ifmovie = "0,0"
    newsyz = 7
    y = 255
    x = 531
    y2 = 334
    x2 = 138
  else
    if whereami = label("exitforest2") then
      ifmovie = "1,exitforest2toforest2"
      newsyz = 7
      y = 228
      x = 171
      y2 = 340
      x2 = 620
    end if
  end if
  egozv = y
  egozh = x
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "forest2" into item 1 of nextroomdata
  walkonby()
end
