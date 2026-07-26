on mouseUp
  global nof, soundspath, effectspath, movienamekeeper, stopornot, globalday
  sprite(the clickOn).visible = 0
  x = "continue"
  zz = 0
  i = 1
  repeat while i <= the number of items in field "jokefield"
    if (item i of field "jokefield" = "1") and (x = "continue") then
      x = "stop"
      put nof into item i of field "jokefield"
      zz = i
    end if
    i = 1 + i
  end repeat
  if zz <> 0 then
    if sprite(30).visible = 1 then
      put "ok" into item 2 of stopornot
      put "ok" into item 1 of stopornot
      window("joke.dxr").windowType = 2
      tell window("joke.dxr")
        set the centerStage to 1
      end tell
      open(window("joke.dxr"))
      tell window("joke.dxr")
        puppetSprite(3, 1)
      end tell
      tell window("joke.dxr")
        set the memberNum of sprite 3 to the number of member ("joke" & globalday & zz)
      end tell
      sound playFile 1, effectspath & "joke.aif"
    end if
  end if
end
