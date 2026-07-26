on exitFrame
  global map, nextroomdata, egozv, egozh, newsyz, syz, inexits, wreck, globalday
  if map = "shore1" then
    put value(item 7 of inexits) + 1 into item 7 of inexits
    if value(item 7 of inexits) = 6 then
      put "0" into item 7 of inexits
    end if
    if value(item 7 of inexits) < 3 then
      repeat with i = 1 to 13
        sprite(i).visible = 1
      end repeat
      repeat with i = 14 to 21
        sprite(i).visible = 0
      end repeat
      sprite(9).visible = 0
    else
      repeat with i = 1 to 3
        sprite(i).visible = 1
      end repeat
      repeat with i = 4 to 9
        sprite(i).visible = 0
      end repeat
      repeat with i = 14 to 18
        sprite(i).visible = 1
      end repeat
      sprite(19).visible = 0
      sprite(20).visible = 0
      sprite(21).visible = 0
    end if
    sprite(21).visible = 0
    sprite(22).visible = 0
    if (item 3 of inexits = "dead") and (globalday = 3) then
      if item 11 of wreck = "0" then
        sprite(21).visible = 1
      else
        sprite(22).visible = 1
      end if
    end if
    go("entershore1")
    newsyz = 5
    syz = 5
    egozv = 308
    egozh = 207
    put "shore1" into item 1 of nextroomdata
  end if
end
