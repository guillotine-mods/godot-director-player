on exitFrame
  global ballpos, miss
  if (the locH of sprite 9 > 629) or (the locV of sprite 9 > 383) then
    if miss = "hezi" then
      miss = "yes"
      go("hezmiss")
    else
      if the locH of sprite 9 > 629 then
        set the locH of sprite 9 to 635
      else
        set the locV of sprite 9 to 392
      end if
      set the memberNum of sprite 9 to the number of member "ballrest"
      go("hatout")
    end if
  else
    set the locH of sprite 9 to the locH of sprite 9 + value(item 5 of ballpos)
    if the locV of sprite 9 < value(item 4 of ballpos) then
      yyy = integer(value(item 6 of ballpos) * 1.14999999999999991)
      put yyy into item 6 of ballpos
      set the locV of sprite 9 to the locV of sprite 9 + yyy
    else
      miss = "hezi"
      put 0 into item 4 of ballpos
      set the locV of sprite 9 to the locV of sprite 9 - value(item 6 of ballpos)
    end if
  end if
  if member(the memberNum of sprite 7).name contains "hezrunR" then
    if the locH of sprite 7 < 640 then
      set the memberNum of sprite 7 to the number of member ("hezrunR" & value(item 1 of field "runcount")) of castLib 1
      set the locH of sprite 7 to the locH of sprite 7 + 20
      put value(item 1 of field "runcount") - 1 into item 1 of field "runcount"
      if value(item 1 of field "runcount") < 1 then
        put 6 into item 1 of field "runcount"
      end if
    end if
  else
    if member(the memberNum of sprite 7).name contains "hezrunL" then
      if the locH of sprite 7 > 355 then
        set the memberNum of sprite 7 to the number of member ("hezrunL" & value(item 1 of field "runcount")) of castLib 1
        set the locH of sprite 7 to the locH of sprite 7 - 20
        put 1 + value(item 1 of field "runcount") into item 1 of field "runcount"
        if value(item 1 of field "runcount") > 6 then
          put 1 into item 1 of field "runcount"
        end if
      end if
    else
      if member(the memberNum of sprite 7).name contains "hezshrt" then
        if value(item 1 of field "runcount") < 7 then
          set the memberNum of sprite 7 to the number of member ("hezshrt" & value(item 1 of field "runcount")) of castLib 1
          hitballshrt(value(item 1 of field "runcount"))
          put 1 + value(item 1 of field "runcount") into item 1 of field "runcount"
        else
          set the memberNum of sprite 7 to the number of member "hezstnd" of castLib 1
        end if
      else
        if member(the memberNum of sprite 7).name contains "hezlong" then
          if value(item 1 of field "runcount") < 7 then
            set the memberNum of sprite 7 to the number of member ("hezlong" & value(item 1 of field "runcount")) of castLib 1
            hitballlong(value(item 1 of field "runcount"))
            put 1 + value(item 1 of field "runcount") into item 1 of field "runcount"
          else
            set the memberNum of sprite 7 to the number of member "hezstnd" of castLib 1
          end if
        end if
      end if
    end if
  end if
end
