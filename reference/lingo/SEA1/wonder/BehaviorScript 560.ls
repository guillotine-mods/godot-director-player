on exitFrame
  global soundspath
  sprite(30).visible = 0
  sprite(31).visible = 0
  sprite(4).visible = 1
  sprite(5).visible = 1
  sprite(18).visible = 1
  sprite(19).visible = 1
  set the volume of sound 2 to 90
  sound playFile 1, soundspath & "eatthis.aif"
end
