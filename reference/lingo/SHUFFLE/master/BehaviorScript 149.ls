on exitFrame
  global foe
  x = "not"
  case item 3 of foe of
    "man":
      foe = "4,1,blk"
    "blk":
      foe = "5,1,fat"
    "fat":
      foe = "2,3,hat"
    "hat":
      foe = "3,3,old"
    "old":
      foe = "4,2,rin"
    "rin":
      foe = "5,2,tof"
    "tof":
      x = "end"
  end case
  if x = "end" then
    foe = "3,2,man"
    go("special")
  else
    sprite(102).visible = 1
    repeat with i = 1 to 20
      puppetSprite(i, 0)
    end repeat
    go("mainmenu")
    sprite(100).visible = 1
    set the locH of sprite 4 to 197
    set the locV of sprite 4 to 360
    set the locH of sprite 11 to 197
    set the locV of sprite 11 to 360
    put the locH of sprite 4 into item 1 of sfl2
    put the locV of sprite 4 into item 2 of sfl2
    put 0 into item 3 of sfl
    updateStage()
  end if
end
