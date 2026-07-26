on exitFrame
  global nextroomdata, egozv, egozh, newsyz, syz
  soundspath("days")
  newsyz = 6
  syz = 6
  egozv = 308
  egozh = 207
  go("shore2downdeck", "day1.dir")
  puppetSprite(30, 1)
  set the memberNum of sprite 30 to the number of member "standright6" of castLib 1
  sprite(30).visible = 1
  put "shore2" into item 1 of nextroomdata
  cursorfunk()
  displayobject()
end
