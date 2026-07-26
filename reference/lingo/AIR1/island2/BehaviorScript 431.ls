on mouseUp
  global objectxx, objectyy, soundspath
  if the clickOn > 102 then
    if sprite the clickOn intersects 100 then
      set the memberNum of sprite 100 to the number of member "piphead2" of castLib "master"
      x = the memberNum of sprite the clickOn
      x = member(x, "master").name
      soundspath("days")
      sound playFile 1, soundspath & "pi" & x & ".aif"
      soundspath("air")
    else
      r = "not"
      if sprite the clickOn intersects 7 then
        r = "yes"
      end if
      if r = "yes" then
        sound playFile 1, soundspath & "guard7.aif"
        set the locH of sprite the clickOn to objectxx
        set the locV of sprite the clickOn to objectyy
        updateStage()
        play frame "guardspk"
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
