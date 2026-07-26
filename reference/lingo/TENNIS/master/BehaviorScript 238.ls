on mouseUp
  sprite(102).visible = 1
  repeat with i = 1 to 20
    puppetSprite(i, 0)
    sprite(i).visible = 1
  end repeat
  go(1)
  updateStage()
end
