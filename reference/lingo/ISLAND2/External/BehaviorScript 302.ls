on mouseUp
  global wreck, egozh, egozv, whatodo, nextroomdata, ifmovie, soundspath
  if item 8 of wreck = "0" then
    nextroomdata = "000"
    if (egozv <> 308) and (egozh <> 535) then
      ifmovie = "1,shore2updeck"
      egozv = 308
      egozh = 535
      walkonby()
    else
      if whatodo = "stand" then
        sprite(30).visible = 0
        sound playFile 1, soundspath & "hezskul1.aif"
        play frame "hezskullspk"
        sprite(30).visible = 1
        put "1" into item 8 of wreck
      end if
    end if
  else
    if item 8 of wreck = "1" then
      sprite(4).visible = 0
      put "found" into item 8 of wreck
      x = "continue"
      repeat with i = 1 to the number of lines in field "objectsfield" of castLib "master"
        if (line i of field "objectsfield" of castLib "master" = "empty") and (x = "continue") then
          put "diving" into line i of field "objectsfield" of castLib "master"
          x = "stop"
        end if
      end repeat
      put "done" into item 2 of line 2 of field "Dprocess" of castLib "master"
      x = value(the text of field "points" of castLib "master")
      x = x + 1
      if x < 10 then
        put "00" & x into field "points" of castLib "master"
      else
        put "0" & x into field "points" of castLib "master"
      end if
      displayobject()
      sound playFile 1, soundspath & "pfdiving.aif"
    else
      nextroomdata = "000"
      if (egozv <> 308) and (egozh <> 535) then
        ifmovie = "1,shore2updeck"
        egozv = 308
        egozh = 535
        walkonby()
      else
        if whatodo = "stand" then
          sprite(30).visible = 0
          sound playFile 1, soundspath & "hezskul2.aif"
          play frame "hezskullspk"
          sprite(30).visible = 1
        end if
      end if
    end if
  end if
end
