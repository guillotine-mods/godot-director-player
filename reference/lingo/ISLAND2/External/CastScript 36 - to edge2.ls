on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie
  if whereami = label("edge1") then
    ifmovie = "0,0"
    newsyz = 9
    y = 400
    x = 370
    y2 = 395
    x2 = 300
  else
    if whereami = label("lighthouse") then
      ifmovie = "1,edge2down"
      newsyz = 7
      y = 390
      x = 30
      y2 = 292
      x2 = 568
    end if
  end if
  egozv = y
  egozh = x
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "edge2" into item 1 of nextroomdata
  walkonby()
end
