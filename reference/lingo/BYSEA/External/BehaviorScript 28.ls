on enterFrame
  global effectspath, whichsnd
  repeat with i = 1 to 40
    sprite(i).visible = 1
  end repeat
  sound playFile 2, effectspath & "rocks.aif"
end
