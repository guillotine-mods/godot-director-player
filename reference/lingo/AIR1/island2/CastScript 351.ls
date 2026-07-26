on mouseUp
  global catgame, soundspath
  catgame = "stone"
  sound playFile 1, soundspath & "choose3.aif"
  go("game2cont1")
end
