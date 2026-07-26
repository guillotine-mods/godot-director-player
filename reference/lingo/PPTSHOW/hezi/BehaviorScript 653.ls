on exitFrame
  global globalday
  repeat with i = 41 to 47
    sprite(i).visible = 0
  end repeat
  if globalday = 1 then
    sprite(41).visible = 1
    sprite(42).visible = 1
    sprite(43).visible = 1
  else
    if globalday = 2 then
      sprite(41).visible = 1
      sprite(42).visible = 1
      sprite(43).visible = 1
      sprite(44).visible = 1
      sprite(45).visible = 1
      sprite(46).visible = 1
    else
      if globalday = 3 then
        sprite(41).visible = 1
        sprite(42).visible = 1
        sprite(43).visible = 1
        sprite(44).visible = 1
        sprite(45).visible = 1
        sprite(46).visible = 1
        sprite(47).visible = 1
      end if
    end if
  end if
end
