on exitFrame
  global wreck, inexits
  if sprite(4).visible = 0 then
    sprite(7).visible = 0
    sprite(23).visible = 1
    sprite(13).visible = 0
  else
    sprite(7).visible = 1
    sprite(13).visible = 1
    sprite(23).visible = 0
  end if
  if (item 10 of wreck = "2") or (item 10 of wreck = "4") then
    if value(item 7 of inexits) > 2 then
      sprite(19).visible = 1
      sprite(14).visible = 0
      sprite(9).visible = 0
    else
      sprite(9).visible = 1
      sprite(19).visible = 0
    end if
  end if
  if (item 10 of wreck = "3") or (item 10 of wreck = "4") then
    sprite(20).visible = 1
  end if
  go("shore1")
end
