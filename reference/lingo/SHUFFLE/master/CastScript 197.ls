on mouseUp
  global sfl, sfl2, foe, effectspath
  set the locH of sprite 4 to 197
  set the locV of sprite 4 to 360
  put the locH of sprite 4 into item 1 of sfl2
  put the locV of sprite 4 into item 2 of sfl2
  puppetSprite(101, 1)
  set the memberNum of sprite 101 to the number of member "hez"
  put 0 into item 3 of sfl
  puppetSprite(6, 1)
  put 0 into field "hatscore"
  put 0 into field "hezscore"
  puppetSprite(4, 1)
  puppetSprite(11, 1)
  sprite(4).visible = 0
  set the moveableSprite of sprite 6 to 1
  sound playFile 2, effectspath & "arcade.aif"
  set the constraint of sprite 6 to 2
  set the constraint of sprite 7 to 2
  go(marker(1))
end
