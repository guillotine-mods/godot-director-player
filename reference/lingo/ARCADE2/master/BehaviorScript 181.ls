on exitFrame
  set the keyDownScript to "gun"
  sprite(5).visible = 0
  sprite(6).visible = 0
  repeat with i = 8 to 30
    sprite(i).visible = 1
  end repeat
  repeat with i = 23 to 33
    sprite(i).visible = 0
  end repeat
  puppetSprite(40, 1)
end
