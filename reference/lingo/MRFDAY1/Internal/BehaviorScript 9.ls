on exitFrame
  global syz, meetings, egozv, egozh, newsyz, nextroomdata
  put "done" into item 3 of meetings
  newsyz = 8
  nextroomdata = "gate,310,328"
  syz = 8
  egozh = 310
  egozv = 328
  go("gate", "day1.dir")
  puppetSprite(30, 1)
  set the memberNum of sprite 30 to the number of member "standright8"
  updateStage()
  sprite(30).visible = 1
  displayobject()
  cursorfunk()
end
