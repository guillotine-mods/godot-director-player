on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie
  if whereami = label("recept") then
    ifmovie = "1,recepttohall"
    newsyz = 5
    y = 191
    x = 341
    y2 = 400
    x2 = 13
  else
    if whereami = label("prosdor") then
      ifmovie = "1,downstairs1"
      newsyz = 4
      y = 333
      x = 313
      y2 = 295
      x2 = 234
    else
      if whereami = label("arcade") then
        ifmovie = "1,fromarcade"
        newsyz = 4
        y = 215
        x = 552
        y2 = 333
        x2 = 306
      else
        if whereami = label("lib") then
          ifmovie = "0,0"
          go("fromlib")
          newsyz = 4
          y = 333
          x = 306
          y2 = 333
          x2 = 306
        end if
      end if
    end if
  end if
  egozv = y
  egozh = x
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "hall" into item 1 of nextroomdata
  walkonby()
end
