on mouseUp
  global SaveNames, OBJECTSFOUND, saveA, saveC, saveD, saveE, saveB, saveNum, globalday, Whichins2, Whichins, savepath
  repeat with i = 28 to 35
    if sprite(i).visible = 1 then
      x = i
    end if
  end repeat
  x = x - 27
  put field("save" & x, 1) into item x of SaveNames
  saveA = field("save" & x, 1)
  saveNum = x
  go("dosave", savepath & "hezsave.dir")
end
