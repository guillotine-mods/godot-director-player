on mouseUp
  global soundspath
  sound playFile 1, soundspath & "artjoys1.aif"
  puppetSprite(11, 0)
  set the cursor of sprite 11 to [1, 1]
  set the cursor of sprite 10 to [1, 1]
  set the cursor of sprite 9 to [1, 1]
  go("givjoy")
end
