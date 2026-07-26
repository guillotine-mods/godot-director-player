on exitFrame
  global syz, meetings, egozv, egozh, newsyz, nextroomdata
  put "done" into item 5 of meetings
  newsyz = 7
  nextroomdata = "shore2,520,300"
  syz = 7
  egozh = 520
  egozv = 300
  go("shore2", "night1.dir")
  puppetSprite(30, 1)
  set the memberNum of sprite 30 to the number of member "standleft7"
  updateStage()
  sprite(30).visible = 1
  displayobject()
  cursorfunk()
end
