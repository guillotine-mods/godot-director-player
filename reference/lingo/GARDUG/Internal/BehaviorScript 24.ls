on exitFrame
  global syz, meetings, egozv, egozh, newsyz, nextroomdata
  put "done" into item 8 of meetings
  newsyz = 9
  nextroomdata = "edge1,300,373"
  syz = 9
  egozh = 300
  egozv = 373
  go("edge1", "night1.dir")
  puppetSprite(30, 1)
  set the memberNum of sprite 30 to the number of member "standright9"
  updateStage()
  sprite(30).visible = 1
  displayobject()
  cursorfunk()
end
