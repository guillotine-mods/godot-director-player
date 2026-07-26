on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie, globalnight, globalday, meetings, soundspath
  r = "sleepnow"
  if globalday = 1 then
    repeat with i = 1 to the number of items in meetings
      if item i of meetings <> "done" then
        r = "notyet"
      end if
    end repeat
  else
    if globalday = 2 then
      repeat with i = 1 to the number of items in line 5 of field "Dprocess" of castLib "master"
        if item i of line 5 of field "Dprocess" of castLib "master" <> "done" then
          r = "notyet"
        end if
      end repeat
      repeat with i = 1 to the number of items in meetings
        if item i of meetings <> "done" then
          r = "notyet"
        end if
      end repeat
    end if
  end if
  if r = "sleepnow" then
    if whereami = label("path5") then
      ifmovie = "1,gosleep"
      newsyz = 6
      y = 204
      x = 502
      y2 = 360
      x2 = 630
    end if
    egozv = y
    egozh = x
    put x2 into item 2 of nextroomdata
    put y2 into item 3 of nextroomdata
    put "000" into item 1 of nextroomdata
    walkonby()
  else
    sound playFile 1, soundspath & "slpnoty1.aif"
  end if
end
