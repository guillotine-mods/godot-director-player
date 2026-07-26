on exitFrame
  global effectspath
  sound playFile 2, effectspath & "crank.aif"
  set the volume of sound 2 to 255
end
