on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie
  if whereami = label("hall") then
    ifmovie = "1,upstairs1"
    newsyz = 8
    y = 294
    x = 237
    y2 = 331
    x2 = 319
  end if
  egozv = y
  egozh = x
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "prosdor" into item 1 of nextroomdata
  walkonby()
end
