on exitFrame
  repeat with i = 1 to 40
    sprite(i).visible = 1
  end repeat
  sprite(18).visible = 0
  sprite(7).visible = 1
  sprite(23).visible = 1
  sprite(16).visible = 0
  sprite(17).visible = 0
  sprite(19).visible = 1
  sprite(13).visible = 1
  sprite(14).visible = 1
  sprite(4).visible = 0
  sprite(3).visible = 0
  sprite(5).visible = 0
  sprite(4).visible = 0
  sprite(6).visible = 1
  go("map")
end
