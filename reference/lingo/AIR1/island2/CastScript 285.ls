on mouseUp
  global catgame, soundspath
  catgame = "stone"
  sound playFile 1, soundspath & "choose2.aif"
  go("game2cont2")
end
