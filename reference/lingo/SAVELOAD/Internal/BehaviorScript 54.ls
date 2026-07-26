on exitFrame
  global cdsavepath
  repeat with i = 10 to 50
    sprite(i).visible = 1
  end repeat
  puppetSprite(57, 0)
  sprite(20).visible = 1
  forget(window(cdsavepath & "saveload.dxr"))
end
