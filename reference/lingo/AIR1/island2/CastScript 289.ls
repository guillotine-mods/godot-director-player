on mouseUp
  global catgame, soundspath
  catgame = "bottom"
  sound playFile 1, soundspath & "choose1.aif"
  go("game1cont")
end
