on exitFrame
  global soundspath
  set the keyDownScript to EMPTY
  sound playFile 1, soundspath & "mnkbad1" & random(3) & ".aif"
end
