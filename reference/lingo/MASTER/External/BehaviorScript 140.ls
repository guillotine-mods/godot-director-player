on exitFrame
  global nextroomdata
  sprite(23).visible = 1
  go(item 1 of nextroomdata)
  sprite(18).visible = 1
  sprite(19).visible = 1
  sprite(20).visible = 1
  sprite(21).visible = 1
  sprite(30).visible = 1
  nextroomdata = "000"
end
