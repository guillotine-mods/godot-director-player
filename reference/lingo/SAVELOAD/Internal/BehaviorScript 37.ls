on mouseUp
  global globalday, effectspath, soundspath, grrr, cdsavepath
  repeat with i = 15 to 30
    sprite(i).visible = 1
  end repeat
  if globalday = 0 then
    tlkpath("strtgame")
    tell the stage
      go(1, cdsavepath & "exodus.dxr")
    end tell
    forget(window(cdsavepath & "saveload.dxr"))
  else
    forget(window(cdsavepath & "saveload.dxr"))
  end if
end
