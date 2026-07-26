on exitFrame
  global syz, meetings, egozv, egozh, newsyz, nextroomdata
  put "done" into item 6 of meetings
  newsyz = 6
  nextroomdata = "loby,490,251"
  syz = 6
  egozh = 490
  egozv = 251
  go("retlobi", "hotel1.dir")
  cursorfunk()
  peoplefunk()
  puppetSprite(30, 1)
  set the memberNum of sprite 30 to the number of member "standleft6"
  updateStage()
  sprite(30).visible = 1
  displayobject()
end
