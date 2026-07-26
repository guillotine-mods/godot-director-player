on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie
  if whereami = label("path4") then
    ifmovie = "1,path4up"
    newsyz = 5
    y = 204
    x = 234
    y2 = 229
    x2 = 284
  else
    if whereami = label("check") then
      ifmovie = "1,checkup"
      newsyz = 5
      y = 242
      x = 544
      y2 = 215
      x2 = 30
    end if
  end if
  egozv = y
  egozh = x
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "path5" into item 1 of nextroomdata
  walkonby()
end
