on exitFrame
  global syz, egozv, egozh, newsyz, nextroomdata
  newsyz = 5
  put "rachbal" into item 1 of nextroomdata
  syz = 5
  soundspath("days")
  go("rachbalout", "day1.dir")
  egozh = 71
  egozv = 288
  puppetSprite(30, 1)
  sprite(30).visible = 1
  cursorfunk()
  displayobject()
end
