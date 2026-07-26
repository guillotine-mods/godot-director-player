on mouseUp
  global objectxx, objectyy, soundspath, egozh, egozv, whatodo, nextroomdata
  if the clickOn > 102 then
    if sprite the clickOn intersects 100 then
      set the memberNum of sprite 100 to the number of member "piphead2" of castLib "master"
      x = the clickOn - 102
      x = line x of field "objectsfield" of castLib "master"
      soundspath("days")
      sound playFile 1, soundspath & "pi" & x & ".aif"
      soundspath("nights")
    else
      r = "not"
      if sprite the clickOn intersects 17 then
        r = "yes"
      end if
      if r = "yes" then
        x = the clickOn - 102
        x = line x of field "objectsfield" of castLib "master"
        if (x = "sulam") and (sprite(17).visible = 1) then
          nextroomdata = "000"
          if (egozv <> 328) or (egozh <> 244) then
            egozv = 328
            egozh = 244
            walkonby()
          else
            if whatodo = "stand" then
              sprite(30).visible = 0
              go("toolstake")
            end if
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
