on exitFrame
  global soundspath
  set the keyDownScript to EMPTY
  sound playFile 1, soundspath & "zigover" & random(5) & ".aif"
end
