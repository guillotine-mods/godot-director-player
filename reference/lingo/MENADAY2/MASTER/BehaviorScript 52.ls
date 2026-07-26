on exitFrame
  global syz, egozv, egozh, newsyz, nextroomdata, meetings
  put "done" into item 3 of meetings
  newsyz = 7
  nextroomdata = "path1,53,285"
  syz = 7
  egozh = 53
  egozv = 285
  go("path1", "day1.dir")
  puppetSprite(30, 1)
  set the memberNum of sprite 30 to the number of member "standright7"
  updateStage()
  sprite(30).visible = 1
  displayobject()
  cursorfunk()
end
