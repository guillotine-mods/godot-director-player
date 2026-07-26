on exitFrame
  global soundspath
  set the keyDownScript to "fromnow"
  sound playFile 1, soundspath & "zigstr2" & random(5) & ".aif"
end
