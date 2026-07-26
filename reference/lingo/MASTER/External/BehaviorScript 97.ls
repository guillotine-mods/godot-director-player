on mouseUp
  global objectxx, objectyy, soundspath
  if sprite the clickOn intersects 100 then
    set the memberNum of sprite 100 to the number of member "piphead2" of castLib "master"
    unu = the memberNum of sprite the clickOn
    x = member(unu, "master").name
    soundspath("days")
    sound playFile 1, soundspath & "pi" & x & ".aif"
    soundspath("air")
  else
    r = "not"
    if sprite the clickOn intersects 14 then
      r = "yes"
    end if
    if r = "yes" then
      unu = the memberNum of sprite the clickOn
      xx = member(unu, "master").name
      i = 1
      repeat while i <= 30
        if line i of field "objectsfield" of castLib "master" = xx then
          x = i
        end if
        i = 1 + i
      end repeat
      planefunk(xx, x)
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
