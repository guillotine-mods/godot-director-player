on exitFrame
  global syz, meetings, egozv, egozh, newsyz, nextroomdata
  put "done" into item 1 of meetings
  newsyz = 6
  nextroomdata = "veranda,234,200"
  syz = 6
  egozh = 234
  egozv = 200
  go(1, "night1.dir")
  peoplefunk()
  puppetSprite(30, 1)
  set the memberNum of sprite 30 to the number of member "standright6"
  updateStage()
  sprite(30).visible = 1
  displayobject()
  cursorfunk()
end
