on mouseUp
  global objectxx, objectyy, soundspath
  if sprite the clickOn intersects 100 then
    set the memberNum of sprite 100 to the number of member "piphead2" of castLib "master"
    x = the memberNum of sprite the clickOn
    x = member(x, "master").name
    sound playFile 1, soundspath & "pi" & x & ".aif"
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
