on exitFrame
  global syz, meetings, egozv, egozh, newsyz, nextroomdata
  put "done" into item 7 of meetings
  newsyz = 9
  nextroomdata = "prosdor,152,334"
  syz = 9
  egozh = 152
  egozv = 334
  go("prosdor", "hotel1.dir")
  puppetSprite(30, 1)
  set the memberNum of sprite 30 to the number of member "standright9"
  sprite(30).visible = 1
  displayobject()
  cursorfunk()
end
