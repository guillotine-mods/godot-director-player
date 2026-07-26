on enterFrame
  global soundspath
  sprite(30).visible = 0
  sprite(31).visible = 1
  sprite(32).visible = 1
  sprite(33).visible = 1
  sound playFile 1, soundspath & "hezifly.aif"
  sound stop 2
end
