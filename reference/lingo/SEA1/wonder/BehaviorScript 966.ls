on exitFrame
  global soundspath
  sound playFile 1, soundspath & "trowmon" & random(6) & ".aif"
  play frame "comon"
  go("throw")
end
