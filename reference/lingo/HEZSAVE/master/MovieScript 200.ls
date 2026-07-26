on cleanup
  global saveA, saveB, saveC, saveD, diskinventory, saveNum, videoinventory, globalday, mission, meetings, TIMEKEEPER, clockspeed, newansglobal, timeguide
  saveNum = 1
  repeat while saveNum <= 8
    put "untitled" into field ("gamename" & saveNum)
    put "08:00" into field ("gametime" & saveNum)
    put the text of field "afganifieldinit" into field ("afganifield" & saveNum)
    put "0,0,0,0,0,0,0,0,0,0" into field ("diskinv" & saveNum)
    put "0,0,0,0,0,0,0,0,0,0" into field ("videoinv" & saveNum)
    put 1 into field ("mission" & saveNum)
    put 1 into field ("whichday" & saveNum)
    put 2 into field ("meetings" & saveNum)
    put "1000" into field ("globalmoney" & saveNum)
    put 630 into field ("clockspeed" & saveNum)
    put "0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0" into field ("newansglobal" & saveNum)
    put "0" into field ("timeguide" & saveNum)
    saveNum = 1 + saveNum
  end repeat
  saveMovie("hezsave.dir")
  play done
end
