on exitFrame
  global tlkpath, optcount
  optcount = 0
  sound playFile 1, tlkpath & "hat31.aif"
  sprite(18).visible = 1
  sprite(19).visible = 1
  sprite(36).visible = 1
  sprite(37).visible = 1
end
