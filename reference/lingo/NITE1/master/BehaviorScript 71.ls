on exitFrame
  global syz, meetings, egozv, egozh, newsyz, nextroomdata
  put "done" into item 1 of meetings
  newsyz = 6
  nextroomdata = "rachbal,320,320"
  syz = 6
  egozh = 320
  egozv = 320
  go("rachbal", "night1.dir")
  puppetSprite(30, 1)
  set the memberNum of sprite 30 to the number of member "standleft6"
  updateStage()
  sprite(30).visible = 1
  displayobject()
  cursorfunk()
end
