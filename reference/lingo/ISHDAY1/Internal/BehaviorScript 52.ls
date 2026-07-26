on exitFrame
  repeat with i = 2 to 40
    sprite(i).visible = 1
    puppetSprite(i, 0)
  end repeat
  repeat with i = 100 to 110
    puppetSprite(i, 0)
  end repeat
end
