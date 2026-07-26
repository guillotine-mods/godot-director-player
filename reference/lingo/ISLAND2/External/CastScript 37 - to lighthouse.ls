on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie
  if whereami = label("edge2") then
    ifmovie = "1,edge2up"
    newsyz = 8
    y = 293
    x = 551
    y2 = 390
    x2 = 30
  else
    if whereami = label("edge3") then
      ifmovie = "1,edge3up"
      newsyz = 5
      y = 218
      x = 160
      y2 = 291
      x2 = 280
    else
      ifmovie = "1,lighthouseout"
      newsyz = 5
      y = 426
      x = 530
      y2 = 291
      x2 = 280
    end if
  end if
  egozv = y
  egozh = x
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "lighthouse" into item 1 of nextroomdata
  walkonby()
end
