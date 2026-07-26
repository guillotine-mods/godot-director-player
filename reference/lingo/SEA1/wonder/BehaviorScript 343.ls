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
      if sprite the clickOn intersects 20 then
        r = "yes"
      end if
      if sprite the clickOn intersects 25 then
        sound playFile 1, soundspath & "ware8.aif"
        set the locH of sprite the clickOn to objectxx
        set the locV of sprite the clickOn to objectyy
        updateStage()
        play frame "dubispk"
      end if
      if r = "yes" then
        put the memberNum of sprite the clickOn
        put the number of member "diving" of castLib "master"
        x = the memberNum of sprite the clickOn
        x = member(x, "master").name
        if x = "diving" then
          sprite(21).visible = 1
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
