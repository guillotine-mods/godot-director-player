on exitFrame
  global syz, meetings, egozv, egozh, newsyz, nextroomdata
  put "done" into item 6 of meetings
  newsyz = 7
  nextroomdata = "path1,40,280"
  syz = 7
  egozh = 40
  egozv = 280
  go("path1", "night1.dir")
  puppetSprite(30, 1)
  set the memberNum of sprite 30 to the number of member "standright7"
  updateStage()
  sprite(30).visible = 1
  displayobject()
  cursorfunk()
end
