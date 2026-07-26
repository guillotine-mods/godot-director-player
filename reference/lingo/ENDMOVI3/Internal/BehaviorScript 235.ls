on exitFrame
  global tlkpath, effectspath
  sound playFile 1, tlkpath & "hez41.aif"
  set the volume of sound 2 to 75
  sound playFile 2, effectspath & "drama.aif"
end
