on mouseUp
  global wreck, soundspath
  if sprite(35).visible = 1 then
    if item 5 of wreck = "1" then
      put "2" into item 5 of wreck
      sound stop 2
      play frame "brjtalk1"
    else
      go(1, "figtbrj.dir")
    end if
  else
    sprite(the clickOn).visible = 0
    updateStage()
    sprite(34).visible = 0
    updateStage()
    put "found" into item 6 of wreck
    x = "continue"
    repeat with i = 1 to the number of lines in field "objectsfield" of castLib "master"
      if (line i of field "objectsfield" of castLib "master" = "empty") and (x = "continue") then
        put "afgan" into line i of field "objectsfield" of castLib "master"
        x = "stop"
      end if
    end repeat
    put "done" into item 3 of line 2 of field "Dprocess" of castLib "master"
    x = value(the text of field "points" of castLib "master")
    x = x + 1
    if x < 10 then
      put "00" & x into field "points" of castLib "master"
    else
      put "0" & x into field "points" of castLib "master"
    end if
    displayobject()
    sound stop 2
    sound playFile 1, soundspath & "pfafgan.aif"
  end if
end
