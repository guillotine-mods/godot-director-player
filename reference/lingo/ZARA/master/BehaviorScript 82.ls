on exitFrame
  global syz, meetings, egozv, egozh, newsyz, nextroomdata
  put "done" into item 5 of meetings
  newsyz = 6
  nextroomdata = "path5,350,213"
  syz = 6
  egozh = 350
  egozv = 213
  go("path5", "night1.dir")
  sprite(15).visible = 0
  puppetSprite(30, 1)
  set the memberNum of sprite 30 to the number of member "standleft6"
  updateStage()
  sprite(30).visible = 1
  displayobject()
  cursorfunk()
end
