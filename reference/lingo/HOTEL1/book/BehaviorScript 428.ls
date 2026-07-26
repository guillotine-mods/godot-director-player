on exitFrame
  global inexits, nextroomdata
  if value(item 6 of inexits) = "4" then
    sprite(18).visible = 0
    sprite(34).visible = 1
  end if
  go(item 1 of nextroomdata)
  sprite(30).visible = 1
  nextroomdata = "000"
end
