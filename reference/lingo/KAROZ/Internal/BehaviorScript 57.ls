on exitFrame
  global syz, meetings, egozv, egozh, newsyz, nextroomdata
  put "done" into item 7 of meetings
  newsyz = 5
  nextroomdata = "edge4,440,220"
  syz = 5
  egozh = 440
  egozv = 220
  go("edge4", "night1.dir")
  puppetSprite(30, 1)
  set the memberNum of sprite 30 to the number of member "standleft5"
  updateStage()
  sprite(30).visible = 1
  displayobject()
  cursorfunk()
end
