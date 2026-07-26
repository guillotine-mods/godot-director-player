on exitFrame
  global syz, meetings, egozv, egozh, newsyz, nextroomdata
  put "done" into item 1 of meetings
  newsyz = 9
  nextroomdata = "clif2,91,336"
  syz = 9
  egozh = 91
  egozv = 336
  go("clif2", "day1.dir")
  puppetSprite(30, 1)
  set the memberNum of sprite 30 to the number of member "standright9"
  sprite(30).visible = 1
  displayobject()
  cursorfunk()
end
