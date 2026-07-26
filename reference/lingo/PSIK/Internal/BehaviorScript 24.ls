on exitFrame
  global syz, meetings, egozv, egozh, newsyz, nextroomdata
  put "done" into item 8 of meetings
  newsyz = 8
  nextroomdata = "swing,60,333"
  syz = 8
  egozh = 60
  egozv = 333
  go("swing", "night1.dir")
  puppetSprite(30, 1)
  set the memberNum of sprite 30 to the number of member "standright8"
  updateStage()
  sprite(30).visible = 1
  displayobject()
  cursorfunk()
end
