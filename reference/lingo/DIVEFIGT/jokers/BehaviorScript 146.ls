on mouseUp
  global effectspath
  sound playFile 1, effectspath & "dive1.aif"
  go(2)
  sprite(10).visible = 1
end
