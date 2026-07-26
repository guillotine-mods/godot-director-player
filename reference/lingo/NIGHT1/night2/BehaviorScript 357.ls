on mouseUp
  global objectxx, objectyy, soundspath, egozh, egozv, whatodo, nextroomdata, ifmovie
  if the clickOn > 102 then
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
      if sprite the clickOn intersects 11 then
        r = "out"
      end if
      if r = "yes" then
        wer = the memberNum of sprite the clickOn
        x = member(wer, "master").name
        if x = "fakbok" then
          nextroomdata = "000"
          if (egozv <> 379) and (egozh <> 93) then
            egozv = 379
            egozh = 93
            walkonby()
          else
            if whatodo = "stand" then
              go("stlbok")
            end if
          end if
        end if
      else
        if r = "out" then
          wer = the memberNum of sprite the clickOn
          x = member(wer, "master").name
          if x = "brkin" then
            nextroomdata = "000"
            if (egozv <> 390) and (egozh <> 550) then
              egozv = 390
              egozh = 550
              walkonby()
            else
              if whatodo = "stand" then
                go("brkindor")
              end if
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
