on mouseUp
  global saveD, saveC, cdsavepath, globalday, effectspath
  repeat with i = 15 to 30
    sprite(i).visible = 1
  end repeat
  forget(window(cdsavepath & "saveload.dxr"))
end
