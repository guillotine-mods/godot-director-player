on exitFrame
  global egozv, egozh, newsyz, nextroomdata
  newsyz = 6
  y = 227
  x = 346
  y2 = 227
  x2 = 346
  updateStage()
  egozv = y
  egozh = x
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "path5" into item 1 of nextroomdata
  walkonby()
  go("path5", "day1.dir")
  puppetSprite(30, 1)
  sprite(30).visible = 1
  nextroomdata = "000"
  cursorfunk()
  displayobject()
end
