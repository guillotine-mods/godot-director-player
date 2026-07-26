on exitFrame
  global soundspath
  set the keyDownScript to EMPTY
  sound playFile 1, soundspath & "mnkbad2" & random(3) & ".aif"
  sound stop 2
end
