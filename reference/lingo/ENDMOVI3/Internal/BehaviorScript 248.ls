on exitFrame
  global effectspath, tlkpath
  set the volume of sound 2 to 75
  sound playFile 1, tlkpath & "hez42.aif"
  sound playFile 2, effectspath & "drama.aif"
end
