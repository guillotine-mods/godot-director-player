on mouseUp
  global objectxx, objectyy, soundspath
  if sprite the clickOn intersects 100 then
    set the memberNum of sprite 100 to the number of member "piphead2" of castLib "master"
    x = the memberNum of sprite the clickOn
    x = member(x, "master").name
    sound playFile 1, soundspath & "pi" & x & ".aif"
  else
    r = "not"
    i = 18
    repeat while (i < 22) and (r = "not")
      if sprite the clickOn intersects i then
        r = "yes"
      end if
      i = i + 1
    end repeat
    if sprite the clickOn intersects 36 or sprite the clickOn intersects 37 then
      r = "yes"
    end if
    if r = "yes" then
      unu = the memberNum of sprite the clickOn
      x = member(unu, "master").name
      sound stop 2
      objecttalktime(x)
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
