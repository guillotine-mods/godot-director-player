on mouseUp
  global soundspath
  sound stop 2
  sound playFile 1, soundspath & "octo" & random(3) & ".aif"
end
