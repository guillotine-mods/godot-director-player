on mouseUp
  soundspath("days")
  sprite(2).volume = 255
  go("arcade", "hotel1.dir")
  puppetSprite(30, 1)
  set the memberNum of sprite 30 to the number of member "standright5"
  sprite(30).visible = 1
  cursorfunk()
  displayobject()
end
