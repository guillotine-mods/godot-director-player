on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie
  if whereami = label("edge3") then
    ifmovie = "0,0"
    newsyz = 9
    y = 384
    x = 304
    y2 = 395
    x2 = 260
  else
    if whereami = label("rachbal") then
      ifmovie = "1,rachballeft"
      newsyz = 4
      y = 287
      x = 150
      y2 = 189
      x2 = 450
    else
      ifmovie = "1,fieldup"
      newsyz = 5
      y = 193
      x = 235
      y2 = 247
      x2 = 496
    end if
  end if
  egozv = y
  egozh = x
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "edge4" into item 1 of nextroomdata
  walkonby()
end
