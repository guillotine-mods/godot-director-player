on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie
  if whereami = label("rooma") then
    ifmovie = "1,openver"
    newsyz = 5
    y = 217
    x = 361
    y2 = 169
    x2 = 317
    put "roomb" into item 1 of nextroomdata
  else
    if whereami = label("roomb") then
      ifmovie = "1,roombtover"
      newsyz = 6
      y = 164
      x = 354
      y2 = 234
      x2 = 350
      put "rooma" into item 1 of nextroomdata
    end if
  end if
  egozv = y
  egozh = x
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  walkonby()
end
