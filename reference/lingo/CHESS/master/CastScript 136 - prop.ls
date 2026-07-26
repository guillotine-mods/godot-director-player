on mouseUp
  global soundspath
  puppetSprite(11, 1)
  set the locH of sprite 11 to 340
  set the locV of sprite 11 to 250
  set the memberNum of sprite 11 to the number of member "propcard"
  set the cursor of sprite 11 to [1, 1]
  set the cursor of sprite 10 to [1, 1]
  set the cursor of sprite 9 to [1, 1]
  go(marker(1))
end
