on exitFrame
  global syz, meetings, egozv, egozh, newsyz, nextroomdata
  put "done" into item 2 of meetings
  newsyz = 9
  nextroomdata = "edge5,174,342"
  syz = 9
  egozh = 174
  egozv = 342
  go("edge5", "day1.dir")
  peoplefunk()
  puppetSprite(30, 1)
  set the memberNum of sprite 30 to the number of member "standright9"
  updateStage()
  sprite(30).visible = 1
  displayobject()
  cursorfunk()
end
