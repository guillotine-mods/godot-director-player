on exitFrame
  x = 0
  repeat with i = 8 to 13
    if sprite(i).visible = 0 then
      x = 1 + x
      sprite(i + 15).visible = 0
    end if
  end repeat
  if x = 6 then
    repeat with i = 8 to 30
      sprite(i).visible = 1
    end repeat
    puppetSprite(7, 0)
    go("end2")
  else
    go(marker("stg2go") + 1)
  end if
end
