on exitFrame
  global soundspath, effectspath
  sound playFile 2, effectspath & "sky.aif"
  sound playFile 1, soundspath & "onwayout.aif"
end
