on enterFrame
  global ballpos, miss, runcount, loser
  if (the locH of sprite 9 < 11) or (the locV of sprite 9 > 387) then
    if miss = "hatuli" then
      miss = "yes"
      go("hatmiss")
    else
      if the locH of sprite 9 < 11 then
        set the locH of sprite 9 to 10
      else
        set the locV of sprite 9 to 392
      end if
      set the memberNum of sprite 9 to the number of member "ballrest"
      go("hezout")
    end if
  else
    set the locH of sprite 9 to the locH of sprite 9 - value(item 7 of ballpos)
    if the locV of sprite 9 > value(item 4 of ballpos) then
      yyy = integer(value(item 8 of ballpos) / 1.12000000000000011)
      put yyy into item 8 of ballpos
      set the locV of sprite 9 to the locV of sprite 9 - yyy
    else
      put 500 into item 4 of ballpos
      if the locV of sprite 9 < value(item 6 of ballpos) then
        yyy = integer(value(item 8 of ballpos) * 1.30000000000000004)
        put yyy into item 8 of ballpos
        set the locV of sprite 9 to the locV of sprite 9 + yyy
      else
        miss = "hatuli"
        put -30 into item 4 of ballpos
        yyy = integer(value(item 8 of ballpos) / 1.12000000000000011)
        put yyy into item 8 of ballpos
        set the locV of sprite 9 to the locV of sprite 9 - yyy
      end if
    end if
  end if
  if the locH of sprite 13 < (value(item 5 of ballpos) - 40) then
    set the locH of sprite 13 to the locH of sprite 13 + 15
    set the memberNum of sprite 13 to the number of member ("hatrun" & value(item 2 of runcount))
    put 1 + value(item 2 of runcount) into item 2 of runcount
    if value(item 2 of runcount) > 6 then
      put 1 into item 2 of runcount
    end if
  else
    if (the locH of sprite 13 > (value(item 5 of ballpos) + 10)) and (value(item 5 of ballpos) > 10) then
      set the locH of sprite 13 to the locH of sprite 13 - 15
      set the memberNum of sprite 13 to the number of member ("hatrun" & value(item 2 of runcount))
      put 1 + value(item 2 of runcount) into item 2 of runcount
      if value(item 2 of runcount) > 6 then
        put 1 into item 2 of runcount
      end if
    else
      if ((the locH of sprite 9 - the locH of sprite 13) < 150) and (loser <> 0) then
        set the memberNum of sprite 13 to the number of member ("hatshrt" & item 3 of runcount) of castLib 1
        hathitball(item 3 of runcount)
        put 1 + value(item 3 of runcount) into item 3 of runcount
        if value(item 3 of runcount) > 6 then
          set the memberNum of sprite 13 to the number of member "hatstnd"
        end if
      end if
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
          put 1 + value(item 1 of field "runcount") into item 1 of field "runcount"
        else
          set the memberNum of sprite 7 to the number of member "hezstnd" of castLib 1
        end if
      else
        if member(the memberNum of sprite 7).name contains "hezlong" then
          if value(item 1 of field "runcount") < 7 then
            set the memberNum of sprite 7 to the number of member ("hezlong" & value(item 1 of field "runcount")) of castLib 1
            put 1 + value(item 1 of field "runcount") into item 1 of field "runcount"
          else
            set the memberNum of sprite 7 to the number of member "hezstnd" of castLib 1
          end if
        end if
      end if
    end if
  end if
end
