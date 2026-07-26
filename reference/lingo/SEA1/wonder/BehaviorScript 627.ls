on mouseUp
  global objectxx, objectyy, wreck, soundspath
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
      if sprite the clickOn intersects 15 then
        r = "yes"
      end if
      if r = "yes" then
        set the locH of sprite the clickOn to objectxx
        set the locV of sprite the clickOn to objectyy
        updateStage()
        x = the memberNum of sprite the clickOn
        x = member(x, "master").name
        if x = "stick" then
          repeat with i = 1 to the number of lines in field "objectsfield" of castLib "master"
            if line i of field "objectsfield" of castLib "master" = "stick" then
              objplc = i
            end if
          end repeat
          repeat with i = objplc + 1 to the number of lines in field "objectsfield" of castLib "master"
            put line i of field "objectsfield" of castLib "master" into line i - 1 of field "objectsfield" of castLib "master"
          end repeat
          put "empty" into line the number of lines in field "objectsfield" of castLib "master" of field "objectsfield" of castLib "master"
          put "found" into item 7 of wreck
          x = "continue"
          repeat with i = 1 to the number of lines in field "objectsfield" of castLib "master"
            if (line i of field "objectsfield" of castLib "master" = "empty") and (x = "continue") then
              put "fire" into line i of field "objectsfield" of castLib "master"
              x = "stop"
            end if
          end repeat
          x = value(the text of field "points" of castLib "master")
          x = x + 1
          if x < 10 then
            put "00" & x into field "points" of castLib "master"
          else
            put "0" & x into field "points" of castLib "master"
          end if
          displayobject()
          sound playFile 1, soundspath & "pffire.aif"
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
