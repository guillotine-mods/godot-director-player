on exitFrame
  global egozv, egozh, wreck, nextroomdata, ifmovie, syz, newsyz
  sprite(13).visible = 1
  y2 = 390
  x2 = 400
  soundspath("days")
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "exitforest2" into item 1 of nextroomdata
  nextroomdata = "000"
  set the locV of sprite 30 to egozv
  set the locH of sprite 30 to egozh
  syz = 9
  newsyz = 9
  go("exitforest2b4", "day1.dir")
  egozv = 390
  egozh = 400
  puppetSprite(30, 1)
  set the locV of sprite 30 to egozv
  set the locH of sprite 30 to egozh
  sprite(30).visible = 1
  cursorfunk()
  ifmovie = "0,0"
  displayobject()
end
