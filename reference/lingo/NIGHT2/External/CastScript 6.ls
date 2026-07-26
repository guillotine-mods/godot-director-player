on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie
  if whereami = label("gate") then
    ifmovie = "1,gatetoveranda"
    newsyz = 9
    y = 359
    x = 321
    y2 = 360
    x2 = 600
  end if
  egozv = y
  egozh = x
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "veranda" into item 1 of nextroomdata
  walkonby()
end
