on exitFrame
  global tlkpath, effectspath
  set the volume of sound 2 to 255
  sound playFile 2, tlkpath & "man13.aif"
  sound playFile 3, tlkpath & "chope.aif"
  sound playFile 4, effectspath & "sea2.aif"
end
