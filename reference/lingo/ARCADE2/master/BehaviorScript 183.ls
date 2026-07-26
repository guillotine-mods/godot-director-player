on exitFrame
  x = 0
  repeat with i = 8 to 18
    if sprite(i).visible = 0 then
      x = 1 + x
      sprite(i + 15).visible = 0
    end if
  end repeat
  if x > 10 then
    repeat with i = 8 to 33
      sprite(i).visible = 1
    end repeat
    puppetSprite(7, 0)
    go("end4")
  else
    go("end4")
  end if
end
