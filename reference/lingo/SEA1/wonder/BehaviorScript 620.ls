on mouseUp
  global objectxx, objectyy, soundspath, wreck
  if the clickOn > 102 then
    if sprite the clickOn intersects 100 then
      set the memberNum of sprite 100 to the number of member "piphead2" of castLib "master"
      x = the memberNum of sprite the clickOn
      x = member(x, "master").name
      soundspath("days")
      sound playFile 1, soundspath & "pi" & x & ".aif"
      soundspath("sea")
    else
      r = "not"
      if sprite the clickOn intersects 33 and (sprite(35).visible = 1) then
        r = "yes"
      end if
      if sprite the clickOn intersects 31 then
        if (sprite(35).visible = 0) and (sprite(33).visible = 0) and (item 5 of wreck = "done") and (item 3 of wreck = "found") then
          set the locH of sprite the clickOn to objectxx
          set the locV of sprite the clickOn to objectyy
          updateStage()
          x = the memberNum of sprite the clickOn
          x = member(x, "master").name
          mony = 0
          repeat with i = 1 to the number of lines in field "objectsfield" of castLib "master"
            if line i of field "objectsfield" of castLib "master" = "fire" then
              objplc = i
            end if
          end repeat
          if x = "fire" then
            repeat with i = objplc + 1 to the number of lines in field "objectsfield" of castLib "master"
              put line i of field "objectsfield" of castLib "master" into line i - 1 of field "objectsfield" of castLib "master"
            end repeat
            put "empty" into line the number of lines in field "objectsfield" of castLib "master" of field "objectsfield" of castLib "master"
            displayobject()
            go("shipend")
          else
            sound playFile 1, soundspath & "hezfire3.aif"
          end if
        else
          sound playFile 1, soundspath & "hezneed.aif"
        end if
      else
        if sprite the clickOn intersects 35 and (sprite(35).visible = 1) then
          sound playFile 1, soundspath & "brj" & random(5) & ".aif"
          set the locH of sprite the clickOn to objectxx
          set the locV of sprite the clickOn to objectyy
          updateStage()
          set the memberNum of sprite 100 to the number of member "piphead1" of castLib "master"
          play frame "brjtalk2"
        end if
      end if
    end if
    if r = "yes" then
      if item 5 of wreck = "1" then
        sound stop 2
        put "2" into item 5 of wreck
        set the locH of sprite the clickOn to objectxx
        set the locV of sprite the clickOn to objectyy
        updateStage()
        play frame "brjtalk1"
      else
        go(1, "figtbrj.dir")
      end if
    end if
    set the locH of sprite the clickOn to objectxx
    set the locV of sprite the clickOn to objectyy
    updateStage()
    set the memberNum of sprite 100 to the number of member "piphead1" of castLib "master"
  end if
end

on mouseDown
  global objectxx, objectyy
  objectxx = the locH of sprite the clickOn
  objectyy = the locV of sprite the clickOn
end
