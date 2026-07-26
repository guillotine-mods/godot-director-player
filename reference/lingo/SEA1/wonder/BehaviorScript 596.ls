on exitFrame
  global nextroomdata
  set the visible of sprite 22 to 1
  set the visible of sprite 23 to 1
  set the visible of sprite 24 to 1
  set the visible of sprite 29 to 1
  go(item 1 of nextroomdata)
  set the visible of sprite 30 to 1
  nextroomdata = "000"
end
