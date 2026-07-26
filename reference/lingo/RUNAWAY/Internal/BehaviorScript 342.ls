on exitFrame
  global tlkpath, effectspath
  sound playFile 1, tlkpath & "esh52.aif"
  set the volume of sound 4 to 100
  sound playFile 4, tlkpath & "chope.aif"
end
