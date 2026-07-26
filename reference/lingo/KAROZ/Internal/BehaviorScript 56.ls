on exitFrame
  global syz, meetings, egozv, egozh, newsyz, nextroomdata
  put "done" into item 7 of meetings
  newsyz = 6
  nextroomdata = "rachbal,240,300"
  syz = 6
  egozh = 240
  egozv = 300
  go("rachbal", "night1.dir")
  puppetSprite(30, 1)
  set the memberNum of sprite 30 to the number of member "standright6"
  updateStage()
  sprite(30).visible = 1
  displayobject()
  cursorfunk()
end
