on exitFrame
  global syz, meetings, egozv, egozh, newsyz, nextroomdata
  put "done" into item 2 of meetings
  newsyz = 7
  nextroomdata = "edge6,234,382"
  syz = 7
  egozh = 234
  egozv = 382
  go("edge6", "night1.dir")
  peoplefunk()
  puppetSprite(30, 1)
  set the memberNum of sprite 30 to the number of member "standright7"
  updateStage()
  sprite(30).visible = 1
  displayobject()
  cursorfunk()
end
