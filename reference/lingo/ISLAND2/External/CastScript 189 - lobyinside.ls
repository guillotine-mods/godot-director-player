on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie
  if whereami = label("loby") then
    ifmovie = "1,lobytopath5"
    newsyz = 5
    y = 195
    x = 281
    y2 = 229
    x2 = 284
  end if
  egozv = y
  egozh = x
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "path5" into item 1 of nextroomdata
  walkonby()
end
