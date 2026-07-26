on exitFrame
  x = 0
  repeat with i = 8 to 12
    if the visible of sprite i = 0 then
      x = 1 + x
      set the visible of sprite (i + 15) to 0
    end if
  end repeat
  if x = 5 then
    repeat with i = 8 to 30
      set the visible of sprite i to 1
    end repeat
    puppetSprite(7, 0)
    go("end1")
  else
    go(marker("stg1go") + 1)
  end if
end
