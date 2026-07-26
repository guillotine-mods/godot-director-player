on mouseUp
  global objectxx, objectyy, soundspath, globalnight
  if sprite the clickOn intersects 100 then
    set the memberNum of sprite 100 to the number of member "piphead2" of castLib "master"
    x = the memberNum of sprite the clickOn
    x = member(x, "master").name
    soundspath("days")
    sound playFile 1, soundspath & "pi" & x & ".aif"
    soundspath("nights")
  else
    r = "not"
    if sprite the clickOn intersects 8 then
      r = "yes"
    end if
    if r = "yes" then
      unu = the memberNum of sprite the clickOn
      x = member(unu, "master").name
      if x = "sulam" then
        sprite(17).visible = 1
        put 1 into item 1 of globalnight
        i = 1
        repeat while i <= the number of lines in field "objectsfield" of castLib "master"
          if line i of field "objectsfield" of castLib "master" = "sulam" then
            objplc = i
          end if
          i = 1 + i
        end repeat
        i = objplc + 1
        repeat while i <= the number of lines in field "objectsfield" of castLib "master"
          put line i of field "objectsfield" of castLib "master" into line i - 1 of field "objectsfield" of castLib "master"
          i = 1 + i
        end repeat
        put "empty" into line the number of lines in field "objectsfield" of castLib "master" of field "objectsfield" of castLib "master"
        displayobject()
      end if
    end if
  end if
  set the locH of sprite the clickOn to objectxx
  set the locV of sprite the clickOn to objectyy
  updateStage()
  set the memberNum of sprite 100 to the number of member "piphead1" of castLib "master"
end

on mouseDown
  global objectxx, objectyy
  objectxx = the locH of sprite the clickOn
  objectyy = the locV of sprite the clickOn
end
