on exitFrame
  global nextroomdata, syz
  sprite(22).visible = 0
  syz = 9
  set the memberNum of sprite 30 to the number of member "standright9"
  go("roomb")
  sprite(30).visible = 1
  nextroomdata = "000"
end
