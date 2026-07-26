on exitFrame
  global syz, meetings, egozv, egozh, newsyz, nextroomdata
  put "done" into item 5 of meetings
  newsyz = 5
  nextroomdata = "hall,152,334"
  syz = 5
  egozh = 152
  egozv = 334
  go("hall", "hotel1.dir")
  puppetSprite(30, 1)
  set the memberNum of sprite 30 to the number of member "standleft5"
  updateStage()
  sprite(30).visible = 1
  displayobject()
  cursorfunk()
end
