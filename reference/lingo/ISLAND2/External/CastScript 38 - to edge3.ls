on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie
  if whereami = label("edge4") then
    ifmovie = "0,0"
    newsyz = 9
    y = 400
    x = 340
    y2 = 400
    x2 = 400
  else
    if whereami = label("lighthouse") then
      ifmovie = "1,lighthouseright"
      newsyz = 5
      y = 287
      x = 289
      y2 = 222
      x2 = 130
    end if
  end if
  egozv = y
  egozh = x
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "edge3" into item 1 of nextroomdata
  walkonby()
end
