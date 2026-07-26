on exitFrame
  global egozv, egozh, nextroomdata, syz, newsyz, meetings, wreck, ifmovie
  y2 = 303
  x2 = 233
  put "done" into item 4 of meetings
  syz = 5
  newsyz = 5
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "rachup" into item 1 of nextroomdata
  put "done" into item 12 of wreck
  go("joker", "air1.dir")
  sprite(22).visible = 1
  sprite(23).visible = 1
  sprite(24).visible = 1
  sprite(29).visible = 0
  sprite(14).visible = 0
  egozv = 303
  egozh = 233
  cursorfunk()
  displayobject()
  ifmovie = "0,0"
end
