on exitFrame
  global inexits, usfultalking, usfulline, syz, egozh, egozv
  if sprite(4).visible = 0 then
    sprite(14).visible = 1
  end if
  set the volume of sound 2 to 80
  talkproc("g", "pil-ans", "shore1go")
  if soundBusy(1) then
    hezzz = "left"
    who = item usfultalking of line usfulline of field "pil-ans" of castLib "master"
    if who contains "pil" then
      set the memberNum of sprite 30 to the number of member ("stand" & hezzz & syz) of castLib 1
      set the locV of sprite 30 to egozv
      set the locH of sprite 30 to egozh
      go(who)
    else
      if who contains "pajos" then
        set the memberNum of sprite 30 to the number of member ("stand" & hezzz & syz) of castLib 1
        set the locV of sprite 30 to egozv
        set the locH of sprite 30 to egozh
        play frame who
      else
        if who contains "pahair" then
          set the memberNum of sprite 30 to the number of member ("stand" & hezzz & syz) of castLib 1
          set the locV of sprite 30 to egozv
          set the locH of sprite 30 to egozh
          repeat with i = 1 to the number of lines in field "objectsfield" of castLib "master"
            if line i of field "objectsfield" of castLib "master" = "hair" then
              objplc = i
            end if
          end repeat
          repeat with i = objplc + 1 to the number of lines in field "objectsfield" of castLib "master"
            put line i of field "objectsfield" of castLib "master" into line i - 1 of field "objectsfield" of castLib "master"
          end repeat
          put "empty" into line the number of lines in field "objectsfield" of castLib "master" of field "objectsfield" of castLib "master"
          displayobject()
          put "done" into item 11 of line 6 of field "Dprocess" of castLib "master"
          x = value(the text of field "points" of castLib "master")
          x = x + 1
          if x < 10 then
            put "00" & x into field "points" of castLib "master"
          else
            put "0" & x into field "points" of castLib "master"
          end if
        else
          if who contains "pachoco" then
            set the memberNum of sprite 30 to the number of member ("stand" & hezzz & syz) of castLib 1
            set the locV of sprite 30 to egozv
            set the locH of sprite 30 to egozh
            repeat with i = 1 to the number of lines in field "objectsfield" of castLib "master"
              if line i of field "objectsfield" of castLib "master" = "choco" then
                objplc = i
              end if
            end repeat
            repeat with i = objplc + 1 to the number of lines in field "objectsfield" of castLib "master"
              put line i of field "objectsfield" of castLib "master" into line i - 1 of field "objectsfield" of castLib "master"
            end repeat
            put "empty" into line the number of lines in field "objectsfield" of castLib "master" of field "objectsfield" of castLib "master"
            displayobject()
            put "done" into item 9 of line 6 of field "Dprocess" of castLib "master"
            x = value(the text of field "points" of castLib "master")
            x = x + 1
            if x < 10 then
              put "00" & x into field "points" of castLib "master"
            else
              put "0" & x into field "points" of castLib "master"
            end if
          else
            if hezzz = "left" then
              case syz of
                9:
                  hezspeaks = "-11,-122"
                8:
                  hezspeaks = "-10,-114"
                7:
                  hezspeaks = "-9,-105"
                6:
                  hezspeaks = "-9,-96"
                5:
                  hezspeaks = "-8,-88"
                4:
                  hezspeaks = "-7,-79"
              end case
            else
              case syz of
                9:
                  hezspeaks = "13,-123"
                8:
                  hezspeaks = "12,-114"
                7:
                  hezspeaks = "11,-106"
                6:
                  hezspeaks = "10,-97"
                5:
                  hezspeaks = "9,-88"
                4:
                  hezspeaks = "8,-80"
              end case
            end if
            set the locV of sprite 30 to the locV of sprite 30 + value(item 2 of hezspeaks)
            set the locH of sprite 30 to the locH of sprite 30 + value(item 1 of hezspeaks)
            set the memberNum of sprite 30 to the number of member ("h" & syz & hezzz) of castLib 1
            go("hezspkpil")
          end if
        end if
      end if
    end if
  end if
end
