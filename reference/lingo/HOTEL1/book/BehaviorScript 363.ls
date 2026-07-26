on exitFrame
  global globalday, soundspath, mirror
  mirror = mirror + 1
  if mirror > 6 then
    mirror = 6
  end if
  repeat with i = 40 to 59
    sprite(i).visible = 0
  end repeat
  case item mirror of line globalday of field "mirror" of
    "mpisto":
      x = 48
    "mirror":
      x = 40
    "goldol":
      x = 44
    "mena":
      x = 52
    "bubi":
      x = 42
    "usual":
      x = 50
    "psy":
      x = 58
    "silly":
      x = 46
    "konri":
      x = 54
    "fat":
      x = 56
  end case
  if x = 50 then
    sprite(x).visible = 1
    sprite(x + 1).visible = 1
    sound playFile 1, soundspath & "usual.aif"
    go("heztalk2")
  else
    sprite(x).visible = 1
    sprite(x + 1).visible = 1
    sound playFile 1, soundspath & item mirror of line globalday of field "mirror" & globalday & "1.aif"
  end if
end
