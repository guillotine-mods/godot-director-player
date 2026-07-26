on mouseUp
  global egozv, egozh, nextroomdata, syz, newsyz, meetings, wreck, ifmovie
  y2 = 371
  x2 = 505
  put "done" into item 3 of meetings
  syz = 8
  newsyz = 8
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "forest2" into item 1 of nextroomdata
  put "done" into item 13 of wreck
  go("forest2b4", "night1.dir")
  sprite(22).visible = 1
  sprite(23).visible = 1
  sprite(24).visible = 1
  egozv = 371
  egozh = 505
  puppetSprite(30, 1)
  set the locV of sprite 30 to egozv
  set the locH of sprite 30 to egozh
  sprite(30).visible = 1
  cursorfunk()
  displayobject()
  ifmovie = "0,0"
end
