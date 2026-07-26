on exitFrame
  global SaveNames, globalday, GlobalHour, GlobalSecond
  repeat with i = 29 to 35
    sprite(i).visible = 0
  end repeat
  repeat with i = 1 to 8
    put item i of SaveNames into field ("save" & i) of castLib 1
  end repeat
  sprite(28).visible = 1
  sprite(36).visible = 1
  member("save1").editable = 1
  puppetSprite(56, 1)
  if the movieName contains "night" then
    set the memberNum of sprite 56 to the number of member ("night" & globalday) of castLib 1
  else
    set the memberNum of sprite 56 to the number of member ("day" & globalday) of castLib 1
  end if
end
