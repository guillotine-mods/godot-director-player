on exitFrame
  global syz, egozv, egozh, newsyz, nextroomdata
  newsyz = 8
  put "check" into item 1 of nextroomdata
  syz = 8
  soundspath("days")
  go("returnchess", "day1.dir")
  egozh = 342
  egozv = 319
  puppetSprite(30, 1)
  sprite(30).visible = 1
  displayobject()
  cursorfunk()
end
