on exitFrame
  global soundspath
  set the volume of sound 2 to 100
  sound playFile 4, soundspath & "pipend" & random(3) & ".aif"
end
