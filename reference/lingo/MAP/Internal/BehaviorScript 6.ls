on exitFrame
  global nof, ifmovie
  ifmovie = "0,0"
  x = 1
  y = 0
  puppetSprite(15, 1)
  set the locH of sprite 15 to 1000
  repeat while (x < the number of lines in field "locations") and (y <> "ok")
    if item 1 of line x of field "locations" = nof then
      y = "ok"
      set the locH of sprite 15 to value(item 2 of line x of field "locations")
      set the locV of sprite 15 to value(item 3 of line x of field "locations")
      next repeat
    end if
    x = 1 + x
  end repeat
  repeat with i = 3 to 14
    set the cursor of sprite i to [member("able1").memberNum, member("able2").memberNum]
  end repeat
  sprite(20).visible = 0
  sprite(21).visible = 0
  repeat with i = 6 to 9
    tell the stage
      sprite(i).visible = 1
    end tell
  end repeat
  tell the stage
    sprite(34).visible = 1
  end tell
  tell the stage
    sprite(15).visible = 1
  end tell
  tell the stage
    sprite(16).visible = 1
  end tell
  tell the stage
    sprite(14).visible = 1
  end tell
  tell the stage
    sprite(18).visible = 1
  end tell
  tell the stage
    sprite(19).visible = 1
  end tell
  tell the stage
    sprite(20).visible = 1
  end tell
  tell the stage
    sprite(21).visible = 1
  end tell
end
