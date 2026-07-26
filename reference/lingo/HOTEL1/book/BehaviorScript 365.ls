on exitFrame
  global globalday, soundspath, mirror
  sound playFile 1, soundspath & item mirror of line globalday of field "mirror" & globalday & "2.aif"
end
