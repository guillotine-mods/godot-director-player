on exitFrame
  global syz, egozv, egozh, newsyz, nextroomdata, meetings
  put "done" into item 3 of meetings
  newsyz = 6
  nextroomdata = "edge6,240,400"
  syz = 6
  egozh = 240
  egozv = 400
  go("edge6", "night1.dir")
  puppetSprite(30, 1)
  set the memberNum of sprite 30 to the number of member "standright6"
  updateStage()
  sprite(30).visible = 1
  displayobject()
  cursorfunk()
end
