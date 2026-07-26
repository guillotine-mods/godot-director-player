on mouseUp
  global whereami, newsyz, globalday, wreck, egozh, egozv, whatodo, nextroomdata, ifmovie
  if whereami = label("path3") then
    ifmovie = "1,exitforest2frompath3"
    newsyz = 5
    y = 279
    x = 30
    y2 = 259
    x2 = 399
    egozv = y
    egozh = x
    put x2 into item 2 of nextroomdata
    put y2 into item 3 of nextroomdata
    put "exitforest2" into item 1 of nextroomdata
    walkonby()
  else
    if whereami = label("forest2") then
      if (globalday = 1) and (item 13 of wreck = "0") then
        nextroomdata = "000"
        if (egozv <> 364) and (egozh <> 411) then
          ifmovie = "0,0"
          egozv = 364
          egozh = 411
          walkonby()
        else
          if whatodo = "stand" then
            sprite(30).visible = 0
            go(1, "figtnigt.dir")
          end if
        end if
      else
        ifmovie = "1,exitforest2fromforest2"
        newsyz = 5
        y = 341
        x = 620
        y2 = 245
        x2 = 167
        egozv = y
        egozh = x
        put x2 into item 2 of nextroomdata
        put y2 into item 3 of nextroomdata
        put "exitforest2" into item 1 of nextroomdata
        walkonby()
      end if
    else
      ifmovie = "1,tennisup"
      newsyz = 9
      y = 252
      x = 262
      y2 = 400
      x2 = 350
      egozv = y
      egozh = x
      put x2 into item 2 of nextroomdata
      put y2 into item 3 of nextroomdata
      put "exitforest2" into item 1 of nextroomdata
      walkonby()
    end if
  end if
end
