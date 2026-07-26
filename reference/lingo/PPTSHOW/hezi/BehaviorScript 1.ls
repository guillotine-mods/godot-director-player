on exitFrame
  global syz, egozv, egozh, newsyz, nextroomdata
  soundspath("days")
  newsyz = 6
  put "path5" into item 1 of nextroomdata
  syz = 6
  go("returnpath5", "day1.dir")
  egozh = 342
  egozv = 216
  puppetSprite(30, 1)
  set the memberNum of sprite 30 to the number of member "standleft6"
  sprite(30).visible = 1
  displayobject()
  cursorfunk()
end
