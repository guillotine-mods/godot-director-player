on mouseUp
  global catgame, soundspath
  catgame = "top"
  sound playFile 1, soundspath & "choose1.aif"
  go("game1cont")
end
