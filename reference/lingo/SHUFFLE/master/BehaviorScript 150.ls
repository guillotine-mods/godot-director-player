on exitFrame
  global soundspath, foe
  sprite(100).visible = 0
  sound playFile 1, soundspath & "sfl" & item 3 of foe & "w.aif"
end
