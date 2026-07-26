on exitFrame
  global ches1, ches2, effectspath
  set the volume of sound 2 to 75
  if not soundBusy(2) then
    sound playFile 2, effectspath & "mind.aif"
  end if
  repeat with i = 14 to 17
    puppetSprite(i, 1)
  end repeat
  repeat with i = 23 to 27
    puppetSprite(i, 1)
  end repeat
  repeat with i = 33 to 37
    puppetSprite(i, 1)
  end repeat
  repeat with i = 42 to 45
    puppetSprite(i, 1)
  end repeat
  repeat with i = 48 to 49
    puppetSprite(i, 1)
  end repeat
  puppetSprite(60, 1)
  puppetSprite(61, 1)
  puppetSprite(62, 1)
  x = random(2)
  if x = 1 then
    set the memberNum of sprite 23 to the number of member (ches1 & "fig")
    sprite(23).visible = 1
    put "E1" into item 1 of line 2 of field "board"
  else
    set the memberNum of sprite 37 to the number of member (ches1 & "fig")
    sprite(37).visible = 1
    put "E1" into item 1 of line 3 of field "board"
  end if
  if x = 1 then
    set the memberNum of sprite 42 to the number of member (ches2 & "fig")
    sprite(42).visible = 1
    put "E2" into item 1 of line 4 of field "board"
  else
    set the memberNum of sprite 48 to the number of member (ches2 & "fig")
    sprite(48).visible = 1
    put "E2" into item 1 of line 5 of field "board"
  end if
  set the memberNum of sprite 60 to the number of member (ches1 & "info")
  set the memberNum of sprite 61 to the number of member (ches2 & "info")
  updateStage()
  set the cursor of sprite 4 to [1, 1]
  set the cursor of sprite 5 to [1, 1]
  set the cursor of sprite 6 to [1, 1]
end
