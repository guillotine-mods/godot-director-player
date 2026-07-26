on searchfunk
  global egozh, egozv, whatodo, nextroomdata, soundspath, shelltoday, nof, effectspath
  myline = 0
  yny = the memberNum of sprite the clickOn
  myname = member(yny, "island2").name
  i = 1
  repeat while i <= the number of lines in field "searchinfo"
    if item 1 of line i of field "searchinfo" = myname then
      myline = i
    end if
    i = 1 + i
  end repeat
  if myline <> 0 then
    myx = value(item 2 of line myline of field "searchinfo")
    myy = value(item 3 of line myline of field "searchinfo")
    mydoing = item 4 of line myline of field "searchinfo"
    nextroomdata = "000"
    if (egozv <> myy) and (egozh <> myx) then
      egozv = myy
      egozh = myx
      walkonby()
    else
      if whatodo = "stand" then
        if mydoing = "non" then
          whatsound = item 5 of line myline of field "searchinfo"
          case whatsound of
            "grass":
              sound playFile 1, soundspath & "pgrass" & random(30) & ".aif"
            "stat":
              sound playFile 1, soundspath & "pstat" & random(20) & ".aif"
            "umb":
              sound playFile 1, soundspath & "pumb" & random(6) & ".aif"
            "rock":
              sound playFile 1, soundspath & "prock" & random(6) & ".aif"
            "fence":
              sound playFile 1, soundspath & "pfence" & random(6) & ".aif"
            "azitz":
              sound playFile 1, soundspath & "pazitz" & random(15) & ".aif"
            "swing":
              sound playFile 1, soundspath & "pswing" & random(5) & ".aif"
            "sign":
              sound playFile 1, soundspath & "psign" & random(6) & ".aif"
            "well":
              sound playFile 1, soundspath & "pwell" & random(5) & ".aif"
            "bench":
              sound playFile 1, soundspath & "pbench" & random(7) & ".aif"
            "lite":
              sound playFile 1, soundspath & "plite" & random(5) & ".aif"
            "table":
              sound playFile 1, soundspath & "ptable" & random(6) & ".aif"
            "vilon":
              sound playFile 1, soundspath & "pvilon" & random(3) & ".aif"
            "pic":
              sound playFile 1, soundspath & "ppic" & random(7) & ".aif"
            "drawer":
              sound playFile 1, soundspath & "pdrawer" & random(7) & ".aif"
            "water":
              sound playFile 1, soundspath & "pwater" & random(6) & ".aif"
          end case
        else
          if mydoing contains "dwarf" then
            gamad(mydoing)
          else
            if mydoing = "key" then
              sound playFile 1, soundspath & "tinkkey.aif"
            else
              mydoing = value(mydoing)
              unu = the memberNum of sprite mydoing
              fff = member(unu, "master").name
              if fff = "jokebtl" then
                sss = "gojoking"
                i = 1
                repeat while i <= the number of items in field "jokefield"
                  if nof = item i of field "jokefield" then
                    sss = "wasalready"
                  end if
                  i = 1 + i
                end repeat
                if sss = "gojoking" then
                  sprite(mydoing).visible = 1
                  sound playFile 1, effectspath & "found.aif"
                else
                  sound playFile 1, effectspath & "nofound.aif"
                end if
              else
                if fff = "shell" then
                  gtu = 0
                  i = 1
                  repeat while i <= the number of items in field "shellfield"
                    if item i of field "shellfield" = nof then
                      gtu = "beenhere"
                    end if
                    i = 1 + i
                  end repeat
                  if gtu = 0 then
                    sprite(mydoing).visible = 1
                    sound playFile 1, effectspath & "found.aif"
                  else
                    sound playFile 1, effectspath & "nofound.aif"
                  end if
                end if
              end if
            end if
          end if
        end if
      end if
    end if
  end if
end
