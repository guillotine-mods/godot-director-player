on keyys
  global soundspath
  if (the keyCode = 124) and (item 3 of field "infos" = "0") then
    if the locH of sprite 13 < 430 then
      if value(item 1 of field "infos") > 5 then
        put 1 into item 1 of field "infos"
        xxx = 1
      else
        xxx = value(item 1 of field "infos")
      end if
      set the memberNum of sprite 13 to the number of member ("monkl" & xxx) of castLib 1
      set the locH of sprite 13 to the locH of sprite 13 + 10
      set the locV of sprite 13 to the locV of sprite 13 - 4
      if not soundBusy(1) and (random(3) = 1) then
        sound playFile 1, soundspath & "monkr.aif"
      end if
      put value(item 1 of field "infos") + 1 into item 1 of field "infos"
      put 0 into item 5 of field "infos"
    end if
  else
    if (the keyCode = 123) and (item 3 of field "infos" = "0") then
      if the locH of sprite 13 > 155 then
        if value(item 1 of field "infos") > 5 then
          put 1 into item 1 of field "infos"
          xxx = 1
        else
          xxx = value(item 1 of field "infos")
        end if
        set the memberNum of sprite 13 to the number of member ("monkr" & xxx) of castLib 1
        set the locH of sprite 13 to the locH of sprite 13 - 10
        set the locV of sprite 13 to the locV of sprite 13 + 4
        if not soundBusy(1) and (random(3) = 1) then
          sound playFile 1, soundspath & "monkl.aif"
        end if
        put value(item 1 of field "infos") + 1 into item 1 of field "infos"
        put 0 into item 5 of field "infos"
      end if
    else
      if (the keyCode = 49) and (value(item 2 of field "infos") = 0) then
        set the locV of sprite 13 to the locV of sprite 13 - 17
        put "jmp" into item 3 of field "infos"
        if not soundBusy(1) and (random(2) = 1) then
          sound playFile 1, soundspath & "monkjmp" & random(10) & ".aif"
        end if
        if member(the memberNum of sprite 13).name contains "l" then
          set the memberNum of sprite 13 to the number of member "jmpl" of castLib 1
        else
          set the memberNum of sprite 13 to the number of member "jmpr" of castLib 1
        end if
      end if
    end if
  end if
end
