on exitFrame
  global tlkpath, effectspath
  sound playFile 1, tlkpath & "pat42.aif"
  set the volume of sound 4 to 60
  sound playFile 4, tlkpath & "chope.aif"
end
