on exitFrame
  global syz, meetings, egozv, egozh, newsyz, nextroomdata
  put "done" into item 7 of meetings
  newsyz = 9
  nextroomdata = "edge2,200,373"
  syz = 9
  egozh = 200
  egozv = 373
  go("edge2", "night1.dir")
  puppetSprite(30, 1)
  set the memberNum of sprite 30 to the number of member "standright9"
  updateStage()
  sprite(30).visible = 1
  displayobject()
  cursorfunk()
end
