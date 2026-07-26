on mouseUp
  global saveNum, saveD, saveC, globalday, GlobalHour, GlobalSecond, savepath, Whichins2, Whichins
  repeat with i = 28 to 35
    if sprite(i).visible = 1 then
      x = i
    end if
  end repeat
  x = x - 27
  saveNum = x
  go("doload", savepath & "hezsave.dir")
end
