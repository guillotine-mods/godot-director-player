on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie
  if whereami = label("path4") then
    ifmovie = "1,path4tofield"
    newsyz = 9
    y = 367
    x = 303
    y2 = 380
    x2 = 620
  else
    if whereami = label("edge4") then
      ifmovie = "1,edge4left"
      newsyz = 4
      y = 246
      x = 471
      y2 = 186
      x2 = 202
    end if
  end if
  egozv = y
  egozh = x
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "field" into item 1 of nextroomdata
  walkonby()
end
