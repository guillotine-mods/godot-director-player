on mouseUp
  global egozh, egozv, whatodo, nextroomdata, ifmovie, wreck, soundspath
  if item 8 of wreck = "found" then
    nextroomdata = "000"
    if (egozv <> 346) and (egozh <> 437) then
      egozv = 346
      egozh = 437
      walkonby()
    else
      if whatodo = "stand" then
        sprite(30).visible = 0
        sound playFile 1, soundspath & "hezleave.aif"
        put "found2" into item 8 of wreck
        go("monster")
      end if
    end if
  else
    nextroomdata = "000"
    if (egozv <> 346) and (egozh <> 437) then
      egozv = 346
      egozh = 437
      walkonby()
    else
      if whatodo = "stand" then
        sprite(30).visible = 0
        if (item 8 of wreck <> "found3") and (item 8 of wreck <> 0) then
          sound playFile 1, soundspath & "hezleav2.aif"
          put "found3" into item 8 of wreck
        end if
        puppetSprite(30, 0)
        go("exitcave2")
      end if
    end if
  end if
end
