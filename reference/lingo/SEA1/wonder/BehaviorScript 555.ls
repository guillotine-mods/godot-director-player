on mouseUp
  global objectxx, objectyy, egozh, egozv, whatodo, nextroomdata, ifmovie, wreck, soundspath
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
      if sprite the clickOn intersects 32 then
        r = "yes"
      else
        if sprite the clickOn intersects 6 then
          sound stop 2
          sound playFile 1, soundspath & "dragcard.aif"
        end if
      end if
      if r = "yes" then
        nextroomdata = "000"
        if (egozv <> 99) and (egozh <> 212) then
          egozv = 99
          egozh = 212
          walkonby2()
          sound stop 2
          sound playFile 1, soundspath & "subidea.aif"
        else
          if whatodo = "stand" then
            x = the memberNum of sprite the clickOn
            x = member(x, "master").name
            if x = "edna" then
              set the locH of sprite the clickOn to objectxx
              set the locV of sprite the clickOn to objectyy
              updateStage()
              put "edna" into item 2 of wreck
              repeat with i = 1 to the number of lines in field "objectsfield" of castLib "master"
                if line i of field "objectsfield" of castLib "master" = "edna" then
                  objplc = i
                end if
              end repeat
              repeat with i = objplc + 1 to the number of lines in field "objectsfield" of castLib "master"
                put line i of field "objectsfield" of castLib "master" into line i - 1 of field "objectsfield" of castLib "master"
              end repeat
              put "empty" into line the number of lines in field "objectsfield" of castLib "master" of field "objectsfield" of castLib "master"
              displayobject()
              go("takeedna")
              sprite(38).visible = 0
              sprite(34).visible = 1
            else
              sound stop 2
              sound playFile 1, soundspath & "noocto" & random(3) & ".aif"
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
