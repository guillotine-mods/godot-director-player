on gamad whatgamad
  global soundspath
  if whatgamad = "dwarf1" then
    if (sprite(18).visible = 0) and (sprite(20).visible = 0) then
      x = random(4)
      if x = 3 then
        play frame "bonout2"
      else
        play frame "bonout1"
      end if
      z = random(2)
      z = z + z
      sprite(16 + z).visible = 1
    end if
  else
    if whatgamad = "dwarf2" then
      if (sprite(36).visible = 0) and (sprite(37).visible = 0) then
        play frame "lilout1"
        z = random(2)
        sprite(35 + z).visible = 1
      end if
    else
      sound playFile 1, soundspath & "dwarf" & random(4) & ".aif"
    end if
  end if
end
