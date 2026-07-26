on exitFrame
  global globalday, soundspath, tlkpath, effectspath
  globalday = 1
  tlkpath("s_day1")
  soundspath("days")
  set the volume of sound 2 to 130
  sound playFile 2, effectspath & "sea.aif"
end
