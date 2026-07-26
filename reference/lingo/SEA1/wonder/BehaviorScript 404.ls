on exitFrame
  global nextroomdata
  set the memberNum of sprite 30 to the number of member "standleft"
  go(item 1 of nextroomdata)
  set the visible of sprite 30 to 1
  nextroomdata = "000"
end
