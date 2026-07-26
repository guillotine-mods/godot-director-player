on mouseUp
  global monk, soundspath, monk2, afganicnt
  x = the clickOn - 5
  x = item x of monk2
  x = "plc" & x
  y = value(char 4 of monk)
  sprite(27).visible = 0
  sprite(28).visible = 0
  sprite(29).visible = 0
  repeat with g = 1 to 3
    if item g of monk2 = y then
      zsd = g
    end if
  end repeat
  sprite(26 + value(zsd)).visible = 1
  if x = monk then
    sound playFile 1, soundspath & "future" & random(5) & ".aif"
    play frame "cupend2"
    afganicnt = value(afganicnt) + 1
    if afganicnt > 72 then
      afganicnt = 72
    end if
    sprite(30).visible = 1
    go("insidego")
  else
    sound playFile 1, soundspath & "cuplose.aif"
    play frame "cupend"
    go("headmonk")
  end if
end
