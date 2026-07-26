on exitFrame
  global soundspath
  if (the keyCode = 124) and (item 3 of field "infos" = "0") then
    put 0 into item 2 of field "infos"
    if the locH of sprite 13 < 430 then
      if value(item 1 of field "infos") > 5 then
        put 1 into item 1 of field "infos"
        xxx = 1
      else
        xxx = value(item 1 of field "infos")
      end if
      set the memberNum of sprite 13 to the number of member ("monkl" & xxx) of castLib 1
      set the locH of sprite 13 to the locH of sprite 13 + 10
      set the locV of sprite 13 to the locV of sprite 13 - 3
      put value(item 1 of field "infos") + 1 into item 1 of field "infos"
      if sprite 13 intersects 11 and (item 1 of field "posi" = "4") then
        repeat with i = 1 to 20
          puppetSprite(i, 0)
        end repeat
        go("end" & item 7 of field "infos")
      end if
    end if
  else
    if (the keyCode = 123) and (item 3 of field "infos" = "0") then
      put 0 into item 2 of field "infos"
      if the locH of sprite 13 > 155 then
        if value(item 1 of field "infos") > 5 then
          put 1 into item 1 of field "infos"
          xxx = 1
        else
          xxx = value(item 1 of field "infos")
        end if
        set the memberNum of sprite 13 to the number of member ("monkr" & xxx) of castLib 1
        set the locH of sprite 13 to the locH of sprite 13 - 10
        set the locV of sprite 13 to the locV of sprite 13 + 3
        put value(item 1 of field "infos") + 1 into item 1 of field "infos"
        if sprite 13 intersects 11 and (item 1 of field "posi" = "4") then
          repeat with i = 1 to 20
            puppetSprite(i, 0)
          end repeat
          go("end" & item 7 of field "infos")
        end if
      end if
    else
      if (the keyCode = 126) and (item 3 of field "infos" = "0") then
        x = value(item 4 of field "infos") + 24
        put 0 into item 5 of field "infos"
        if sprite 13 intersects x then
          set the locV of sprite 13 to the locV of sprite 13 - 60
          put value(item 1 of field "posi") + 1 into item 1 of field "posi"
          put value(item 4 of field "infos") + 1 into item 4 of field "infos"
        end if
      else
        if (the keyCode = 125) and (item 3 of field "infos" = "0") then
          x = value(item 4 of field "infos") + 20
          put 0 into item 5 of field "infos"
          if sprite 13 intersects x then
            set the locV of sprite 13 to the locV of sprite 13 + 60
            put value(item 4 of field "infos") - 1 into item 4 of field "infos"
            put value(item 1 of field "posi") - 1 into item 1 of field "posi"
          end if
        else
          if (the keyCode = 49) and (the memberNum of sprite 13 <> the number of member "monkl1") then
          end if
        end if
      end if
    end if
  end if
  if item 3 of field "infos" = "jmp" then
    put value(item 2 of field "infos") + 1 into item 2 of field "infos"
    if value(item 2 of field "infos") > 8 then
      set the memberNum of sprite 13 to the number of member "monkl1"
      set the locV of sprite 13 to the locV of sprite 13 + 17
      updateStage()
      put "0" into item 3 of field "infos"
      put 0 into item 2 of field "infos"
    end if
  end if
  repeat with i = 2 to 5
    if item i of field "posi" = "ok" then
      x = 0
      repeat with j = 2 to 5
        if item j of field "posi" = "4" then
          x = "not"
        end if
      end repeat
      if x = 0 then
        x = random(6)
        if x = 1 then
          put 4 into item i of field "posi"
        end if
      end if
      next repeat
    end if
    if (item i of field "posi" = "4") or (item i of field "posi" = 2) then
      if sprite (i + 3) intersects 22 or sprite (i + 3) intersects 24 then
        set the locV of sprite (i + 3) to the locV of sprite (i + 3) + 60
        put value(item i of field "posi") - 1 into item i of field "posi"
      else
        set the locH of sprite (i + 3) to the locH of sprite (i + 3) + 13
        set the locV of sprite (i + 3) to the locV of sprite (i + 3) - 4
        if sprite (i + 3) intersects 13 and (item i of field "posi" = item 1 of field "posi") then
          if (item 3 of field "infos" = "0") and ((i + 3) <> value(item 6 of field "infos")) then
            put i + 3 into item 6 of field "infos"
            if the visible of sprite 94 = 1 then
              set the visible of sprite 94 to 0
            else
              if the visible of sprite 95 = 1 then
                set the visible of sprite 95 to 0
              else
                if the visible of sprite 96 = 1 then
                  set the visible of sprite 96 to 0
                else
                  repeat with i = 1 to 20
                    puppetSprite(i, 0)
                  end repeat
                  go("loose" & random(2))
                end if
              end if
            end if
          else
            if member(the memberNum of sprite 13).name contains "jmp" then
              put value(the text of field "score") + 1 into field "score"
            end if
          end if
        end if
      end if
      next repeat
    end if
    if sprite (i + 3) intersects 23 then
      set the locV of sprite (i + 3) to the locV of sprite (i + 3) + 60
      put value(item i of field "posi") - 1 into item i of field "posi"
      next repeat
    end if
    if sprite (i + 3) intersects 28 then
      if value(item 6 of field "infos") = (i + 3) then
        put 0 into item 6 of field "infos"
      end if
      put "ok" into item i of field "posi"
      set the locH of sprite (i + 3) to 238
      set the locV of sprite (i + 3) to 106
      next repeat
    end if
    set the locH of sprite (i + 3) to the locH of sprite (i + 3) - 13
    set the locV of sprite (i + 3) to the locV of sprite (i + 3) + 4
    if sprite (i + 3) intersects 13 and (item i of field "posi" = item 1 of field "posi") then
      if (item 3 of field "infos" = "0") and ((i + 3) <> value(item 6 of field "infos")) then
        put i + 3 into item 6 of field "infos"
        if the visible of sprite 94 = 1 then
          sound playFile 1, soundspath & "hitbrl1" & random(3) & ".aif"
          set the visible of sprite 94 to 0
        else
          if the visible of sprite 95 = 1 then
            sound playFile 1, soundspath & "hitbrl2" & random(3) & ".aif"
            set the visible of sprite 95 to 0
          else
            if the visible of sprite 96 = 1 then
              sound playFile 1, soundspath & "hitbrl3" & random(3) & ".aif"
              set the visible of sprite 96 to 0
            else
              sound playFile 1, soundspath & "hitbrl4.aif"
              repeat with i = 1 to 20
                puppetSprite(i, 0)
              end repeat
              go("loose" & random(2))
            end if
          end if
        end if
        next repeat
      end if
      if member(the memberNum of sprite 13).name contains "jmp" then
        put value(the text of field "score") + 1 into field "score"
      end if
    end if
  end repeat
end
