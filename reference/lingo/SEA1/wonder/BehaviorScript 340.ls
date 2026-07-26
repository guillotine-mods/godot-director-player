on exitFrame
  global soundspath
  set the visible of sprite 16 to 1
  set the visible of sprite 9 to 1
  set the visible of sprite 17 to 1
  set the visible of sprite 18 to 1
  set the visible of sprite 19 to 1
  set the visible of sprite 30 to 1
  sound playFile 1, soundspath & "ware6.aif"
  set the visible of sprite 21 to 0
end
