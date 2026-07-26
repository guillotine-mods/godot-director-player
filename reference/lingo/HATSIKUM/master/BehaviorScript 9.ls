on exitFrame
  global optcount, tlkpath
  sound playFile 1, tlkpath & "hat56.aif"
  optcount = 0
  repeat with i = 1 to 40
    sprite(i).visible = 1
  end repeat
end
