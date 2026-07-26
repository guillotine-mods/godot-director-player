on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie
  if whereami = label("prosdor") then
    ifmovie = "1,toroomb"
    newsyz = 6
    y = 252
    x = 217
    y2 = 225
    x2 = 513
  else
    if whereami = label("roomc") then
      ifmovie = "1,roomctoroomb"
      newsyz = 7
      y = 247
      x = 422
      y2 = 283
      x2 = 237
    else
      ifmovie = "1,bathtoroomb"
      newsyz = 7
      y = 371
      x = 406
      y2 = 328
      x2 = 247
    end if
  end if
  egozv = y
  egozh = x
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "roomb" into item 1 of nextroomdata
  walkonby()
end
