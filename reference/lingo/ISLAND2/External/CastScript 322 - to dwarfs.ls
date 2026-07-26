on mouseUp
  global whereami, newsyz, globalday, wreck, egozh, egozv, whatodo, nextroomdata, ifmovie
  if whereami = label("forest1") then
    ifmovie = "1,dwarfdown"
    newsyz = 5
    y = 400
    x = 330
    y2 = 208
    x2 = 201
    egozv = y
    egozh = x
    put x2 into item 2 of nextroomdata
    put y2 into item 3 of nextroomdata
    put "dwarfs" into item 1 of nextroomdata
    walkonby()
  else
    if whereami = label("exitforest3") then
      ifmovie = "0,0"
      newsyz = 9
      y = 400
      x = 620
      y2 = 390
      x2 = 320
      egozv = y
      egozh = x
      put x2 into item 2 of nextroomdata
      put y2 into item 3 of nextroomdata
      put "dwarfs" into item 1 of nextroomdata
      walkonby()
    else
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
        ifmovie = "1,dwarfleft"
        newsyz = 6
        y = 341
        x = 143
        y2 = 256
        x2 = 546
        egozv = y
        egozh = x
        put x2 into item 2 of nextroomdata
        put y2 into item 3 of nextroomdata
        put "dwarfs" into item 1 of nextroomdata
        walkonby()
      end if
    end if
  end if
end
