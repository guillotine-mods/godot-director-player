on mouseUp
  global objectxx, objectyy, usfultalking, usfulobject, wreck, soundspath
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
      if sprite the clickOn intersects 14 or sprite the clickOn intersects 4 then
        r = "yes"
      end if
      if r = "yes" then
        x = the memberNum of sprite the clickOn
        x = member(x, "master").name
        if x = "wine" then
          if (item 10 of wreck = "2") or (item 10 of wreck = "4") then
            put "4" into item 10 of wreck
          else
            put "3" into item 10 of wreck
          end if
          sprite(20).visible = 1
          repeat with i = 1 to the number of lines in field "objectsfield" of castLib "master"
            if line i of field "objectsfield" of castLib "master" = "wine" then
              objplc = i
            end if
          end repeat
          repeat with i = objplc + 1 to the number of lines in field "objectsfield" of castLib "master"
            put line i of field "objectsfield" of castLib "master" into line i - 1 of field "objectsfield" of castLib "master"
          end repeat
          put "empty" into line the number of lines in field "objectsfield" of castLib "master" of field "objectsfield" of castLib "master"
          displayobject()
          set the locH of sprite the clickOn to objectxx
          set the locV of sprite the clickOn to objectyy
          updateStage()
          put "done" into item 8 of line 6 of field "Dprocess" of castLib "master"
          x = value(the text of field "points" of castLib "master")
          x = x + 1
          if x < 10 then
            put "00" & x into field "points" of castLib "master"
          else
            put "0" & x into field "points" of castLib "master"
          end if
          sound stop 2
          sound playFile 1, soundspath & "pltwine.aif"
          if sprite(19).visible = 1 then
            sprite(14).visible = 1
          end if
          play frame "get"
          usfulobject = "wine"
          usfultalking = 1
          go("instruct")
          if sprite(19).visible = 1 then
          end if
        else
          if x = "plthat" then
            if (item 10 of wreck = "3") or (item 10 of wreck = "4") then
              put "4" into item 10 of wreck
            else
              put "2" into item 10 of wreck
            end if
            if sprite(4).visible = 1 then
              sprite(9).visible = 1
            else
              sprite(19).visible = 1
            end if
            repeat with i = 1 to the number of lines in field "objectsfield" of castLib "master"
              if line i of field "objectsfield" of castLib "master" = "plthat" then
                objplc = i
              end if
            end repeat
            repeat with i = objplc + 1 to the number of lines in field "objectsfield" of castLib "master"
              put line i of field "objectsfield" of castLib "master" into line i - 1 of field "objectsfield" of castLib "master"
            end repeat
            put "empty" into line the number of lines in field "objectsfield" of castLib "master" of field "objectsfield" of castLib "master"
            displayobject()
            set the locH of sprite the clickOn to objectxx
            set the locV of sprite the clickOn to objectyy
            updateStage()
            put "done" into item 10 of line 6 of field "Dprocess" of castLib "master"
            x = value(the text of field "points" of castLib "master")
            x = x + 1
            if x < 10 then
              put "00" & x into field "points" of castLib "master"
            else
              put "0" & x into field "points" of castLib "master"
            end if
            sound stop 2
            sound playFile 1, soundspath & "plthatg1.aif"
            play frame "get"
          else
            if sprite(15).visible = 1 then
              sprite(14).visible = 1
            end if
            objecttalktime(x)
          end if
        end if
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
