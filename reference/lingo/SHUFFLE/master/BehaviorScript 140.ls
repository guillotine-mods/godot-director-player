on exitFrame
  global foe
  puppetSprite(100, 1)
  set the memberNum of sprite 100 to the number of member (item 3 of foe & "2")
  puppetSprite(95, 1)
  set the memberNum of sprite 95 to the number of member item 3 of foe
  repeat with i = 103 to 109
    set the visible of sprite i to 0
  end repeat
  case item 3 of foe of
    "man":
      set the visible of sprite 103 to 1
    "blk":
      set the visible of sprite 104 to 1
    "fat":
      set the visible of sprite 105 to 1
    "hat":
      set the visible of sprite 106 to 1
    "old":
      set the visible of sprite 107 to 1
    "rin":
      set the visible of sprite 108 to 1
    "tof":
      set the visible of sprite 109 to 1
  end case
end
