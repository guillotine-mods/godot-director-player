on exitFrame
  global syz, meetings, egozv, egozh, newsyz, nextroomdata
  put "done" into item 5 of meetings
  newsyz = 9
  nextroomdata = "path4,290,350"
  syz = 9
  egozh = 290
  egozv = 350
  go("path4", "day1.dir")
  puppetSprite(30, 1)
  set the memberNum of sprite 30 to the number of member "standright9"
  updateStage()
  sprite(30).visible = 1
  displayobject()
  cursorfunk()
end
