on exitFrame
  global soundspath
  sound stop 2
  sound playFile 1, soundspath & "out" & random(3) & ".aif"
end
