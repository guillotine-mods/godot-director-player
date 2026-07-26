on gamad whatgamad
  if whatgamad = "dwarf1" then
    if (the visible of sprite 18 = 0) and (the visible of sprite 20 = 0) then
      x = random(4)
      if x = 3 then
        play frame "bonout2"
      else
        play frame "bonout1"
      end if
      z = random(2)
      z = z + z
      set the visible of sprite (16 + z) to 1
    end if
  else
    if whatgamad = "dwarf2" then
      if (the visible of sprite 36 = 0) and (the visible of sprite 37 = 0) then
        play frame "lilout1"
        z = random(2)
        set the visible of sprite (35 + z) to 1
      end if
    else
    end if
  end if
end
