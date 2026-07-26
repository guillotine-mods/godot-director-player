on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie
  if whereami = label("forest1") then
    ifmovie = "1,dwarfdown"
    newsyz = 5
    y = 400
    x = 330
    y2 = 208
    x2 = 201
  else
    if whereami = label("exitforest3") then
      ifmovie = "0,0"
      newsyz = 9
      y = 400
      x = 620
      y2 = 390
      x2 = 320
    else
      ifmovie = "1,dwarfleft"
      newsyz = 6
      y = 341
      x = 143
      y2 = 256
      x2 = 546
    end if
  end if
  egozv = y
  egozh = x
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "dwarfs" into item 1 of nextroomdata
  walkonby()
end
