on hitback
  if the keyCode = 124 then
    if the locH of sprite 7 < 640 then
      set the memberNum of sprite 7 to the number of member "hezrunR2" of castLib 1
      set the locH of sprite 7 to the locH of sprite 7 + 15
      put 6 into item 1 of field "runcount"
    end if
  else
    if the keyCode = 123 then
      if the locH of sprite 7 > 325 then
        set the memberNum of sprite 7 to the number of member "hezrunL1" of castLib 1
        set the locH of sprite 7 to the locH of sprite 7 - 15
        put 1 into item 1 of field "runcount"
      end if
    else
      if the keyCode = 49 then
        if (the locV of sprite 9 + 75) < 215 then
          set the memberNum of sprite 7 to the number of member "hezshrt1" of castLib 1
        else
          set the memberNum of sprite 7 to the number of member "hezlong1" of castLib 1
        end if
        put 1 into item 1 of field "runcount"
      end if
    end if
  end if
end
