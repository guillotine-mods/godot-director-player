on exitFrame
  global soundspath, dubi, effectspath
  dubi = 1
  sprite(16).visible = 1
  sprite(9).visible = 1
  sprite(17).visible = 1
  sprite(18).visible = 1
  sprite(19).visible = 1
  sprite(30).visible = 1
  sound playFile 1, soundspath & "ware1.aif"
  sound playFile 2, effectspath & "wreck3.aif"
  sprite(21).visible = 0
end
