on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie
  if whereami = label("prosdor") then
    ifmovie = "1,torooma"
    newsyz = 7
    y = 325
    x = 51
    y2 = 308
    x2 = 124
  else
    if whereami = label("bath") then
      ifmovie = "1,frombath"
      newsyz = 8
      y = 404
      x = 171
      y2 = 400
      x2 = 399
    else
      ifmovie = "1,fromroomc"
      newsyz = 7
      y = 240
      x = 182
      y2 = 254
      x2 = 424
    end if
  end if
  egozv = y
  egozh = x
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "rooma" into item 1 of nextroomdata
  walkonby()
end
