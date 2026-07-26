on exitFrame
  global soundspath
  sound stop 2
  sound playFile 1, soundspath & "sureaaa" & random(5) & ".aif"
end
