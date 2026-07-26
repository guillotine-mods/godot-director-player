on mouseUp
  global egozv, egozh, nextroomdata, wreck, ifmovie
  y2 = 380
  x2 = 610
  put "done" into item 5 of wreck
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "openair3" into item 1 of nextroomdata
  nextroomdata = "000"
  go("openair3a", "sea1.dir")
  if item 5 of wreck = "done" then
    sprite(35).visible = 0
    sprite(36).visible = 0
  end if
  if item 6 of wreck = "found" then
    sprite(33).visible = 0
    sprite(34).visible = 0
  end if
  egozv = 380
  egozh = 610
  puppetSprite(30, 1)
  set the locV of sprite 30 to egozv
  set the locH of sprite 30 to egozh
  sprite(30).visible = 1
  cursorfunk()
  displayobject()
  ifmovie = "0,0"
end
