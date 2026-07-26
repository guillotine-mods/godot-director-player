on exitFrame
  global effectspath
  soundspath("sea")
  put "0" into field "trynum"
  sound playFile 1, effectspath & "wreck3.aif"
  sound playFile 2, effectspath & "action.aif"
end
