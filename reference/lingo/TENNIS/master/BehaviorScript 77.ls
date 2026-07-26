on exitFrame
  global ballpos, miss, effectspath
  miss = "yes"
  puppetSprite(9, 1)
  x = the locH of sprite 13 + 125
  y = 98
  sound playFile 1, effectspath & "raket" & random(3) & ".aif"
  x2 = 315 + random(340)
  y2 = 310 + random(50)
  x4 = (x2 - x) / 11
  y4 = random(4) + 3
  ballpos = x & "," & y & "," & x2 & "," & y2 & "," & x4 & "," & y4
  set the locH of sprite 9 to x
  set the locV of sprite 9 to y
  updateStage()
  viss = the memberNum of sprite 7
  if member(viss, 1).name contains "hezrunR" then
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
