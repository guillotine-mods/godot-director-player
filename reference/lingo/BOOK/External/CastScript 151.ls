on mouseUp
  puppetSprite(10, 0)
  puppetSprite(11, 0)
  sprite(93).visible = 1
  sprite(100).visible = 1
  repeat with i = 103 to 110
    sprite(i).visible = 1
  end repeat
  go("lib")
end
