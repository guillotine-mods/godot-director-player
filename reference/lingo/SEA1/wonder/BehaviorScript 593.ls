on exitFrame
  global soundspath, wreck
  put "1" into item 5 of wreck
  put "1" into item 6 of wreck
  set the volume of sound 2 to 130
  sound playFile 1, soundspath & "brjescp2.aif"
end
