on mouseUp
  global effectspath, newsyz, nextroomdata, syz, egozh, egozv
  repeat with i = 1 to the number of lines in field "locations"
    if item 1 of line i of field "locations" = "field" then
      set the locH of sprite 15 to value(item 2 of line i of field "locations")
      set the locV of sprite 15 to value(item 3 of line i of field "locations")
    end if
  end repeat
  updateStage()
  sound playFile 1, effectspath & "movemap.aif"
  newsyz = 9
  syz = 9
  y2 = 350
  x2 = 290
  egozv = 350
  egozh = 290
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "path4" into item 1 of nextroomdata
  tell the stage
    sprite(30).visible = 0
  end tell
  tell the stage
    set the memberNum of sprite 30 to the number of member "standleft9"
  end tell
  tell the stage
    set the locH of sprite 30 to x2
  end tell
  tell the stage
    set the locV of sprite 30 to y2
  end tell
  tell the stage
    peoplefunk()
  end tell
  tell the stage
    rir = the movieName
  end tell
  if (rir contains "night1") or (rir = "day1.dxr") then
    tell the stage
      go(item 1 of nextroomdata)
    end tell
  end if
  tell the stage
    sprite(30).visible = 1
  end tell
  nextroomdata = "000"
  forget(window("map.dxr"))
end
