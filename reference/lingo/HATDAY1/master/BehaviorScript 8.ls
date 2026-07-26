on exitFrame
  global tlkpath, optcount
  sound playFile 1, tlkpath & "hat1b.aif"
  optcount = 0
  sprite(19).visible = 1
  sprite(18).visible = 1
  sprite(20).visible = 1
  sprite(21).visible = 1
end
