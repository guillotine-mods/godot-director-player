on exitFrame
  global syz, meetings, egozv, egozh, newsyz, nextroomdata
  put "done" into item 2 of meetings
  newsyz = 7
  nextroomdata = "forest2,290,380"
  syz = 7
  egozh = 290
  egozv = 380
  go("forest2", "day1.dir")
  puppetSprite(30, 1)
  set the memberNum of sprite 30 to the number of member "standright7"
  updateStage()
  sprite(30).visible = 1
  displayobject()
  cursorfunk()
end
