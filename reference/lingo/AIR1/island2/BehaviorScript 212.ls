on exitFrame
  global egozv, egozh, newsyz, nextroomdata
  soundspath("s_days")
  go("rachbalout", "day1.dir")
  egozh = 71
  egozv = 288
  puppetSprite(30, 1)
  sprite(30).visible = 1
  cursorfunk()
  displayobject()
end
