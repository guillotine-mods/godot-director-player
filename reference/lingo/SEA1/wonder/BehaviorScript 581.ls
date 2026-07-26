on mouseUp
  global objectxx, objectyy, soundspath
  if the clickOn > 102 then
    if sprite the clickOn intersects 100 then
      set the memberNum of sprite 100 to the number of member "piphead2" of castLib "master"
      x = the memberNum of sprite the clickOn
      x = member(x, "master").name
      sound playFile 1, soundspath & "pi" & x & ".aif"
    else
      r = "not"
      if sprite the clickOn intersects 11 then
        r = "yes"
      end if
      if r = "yes" then
        yyu = the memberNum of sprite the clickOn
        x = member(yyu, "master").name
        if x = "glass" then
          mony = 0
          repeat with i = 1 to the number of lines in field "objectsfield" of castLib "master"
            if line i of field "objectsfield" of castLib "master" = "glass" then
              objplc = i
            end if
            if line i of field "objectsfield" of castLib "master" = "money1" then
              mony = "yes"
            end if
            if line i of field "objectsfield" of castLib "master" = "money2" then
              mony = "yes"
            end if
          end repeat
          repeat with i = objplc + 1 to the number of lines in field "objectsfield" of castLib "master"
            put line i of field "objectsfield" of castLib "master" into line i - 1 of field "objectsfield" of castLib "master"
          end repeat
          yye = the number of lines in field "objectsfield" of castLib "master"
          put "empty" into line yye of field "objectsfield" of castLib "master"
          displayobject()
          if mony = "yes" then
            go(marker(1))
            sound playFile 1, soundspath & "dubmony2.aif"
            go("dubitlkmon")
          else
            go("dubileave")
          end if
        else
          sound playFile 1, soundspath & "dubmony4.aif"
          go("dubitlk")
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
