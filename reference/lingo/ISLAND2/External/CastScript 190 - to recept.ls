on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie
  if whereami = label("hall") then
    ifmovie = "1,receptfromhall"
    newsyz = 5
    y = 400
    x = 40
    y2 = 194
    x2 = 368
  else
    if whereami = label("loby") then
      ifmovie = "1,lobytorecept"
      newsyz = 9
      y = 273
      x = 480
      y2 = 360
      x2 = 50
    else
    end if
  end if
  egozv = y
  egozh = x
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "recept" into item 1 of nextroomdata
  walkonby()
end
