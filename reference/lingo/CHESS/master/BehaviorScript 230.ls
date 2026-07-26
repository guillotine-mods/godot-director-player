on mouseUp
  global soundspath
  repeat with i = 11 to 62
    puppetSprite(i, 0)
    sprite(i).visible = 0
  end repeat
  set the volume of sound 2 to 255
  go(1)
end
